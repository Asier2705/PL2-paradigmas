#include <iostream>
#include <cmath>
#include <cuda_runtime.h>

#include "fase1_despegues.h"
#include "info_gpu.h"
#include "cloud_envio.h"

//Este es el kernel principal. Cada hilo coge un vuelo y comprueba si se pasa del límite
__global__ void filtrar_despegues_gpu(const float* array_retrasos, int total_vuelos, int limite_minutos) {

    //Calculamos qué vuelo le toca exactamente a este hilo
    int id_hilo = blockIdx.x * blockDim.x + threadIdx.x;

    //Si nos salimos de la cantidad real de vuelos, apagamos el hilo para no leer basura en memoria
    if (id_hilo >= total_vuelos) {
        return;
    }

    float minutos = array_retrasos[id_hilo];

    //El CSV tiene huecos en blanco por lo que si leemos un NaN, pasamos al siguiente
    if (isnan(minutos)) {
        return;
    }

    //Comprobamos la lógica:
    //Si buscamos retrasos (positivo): que el vuelo tarde igual o más que el límite
    //Si buscamos adelantos (negativo): que salga incluso antes (menor o igual)
    if ((limite_minutos >= 0 && minutos >= limite_minutos) ||
        (limite_minutos < 0 && minutos <= limite_minutos)) {

        //Imprimimos directo desde la gráfica
        printf("Hilo global %d -> DEP_DELAY = %.2f\n", id_hilo, minutos);
    }
}

void lanzar_fase1(const DatosVuelos& datos) {
    if (datos.num_filas == 0) {
        std::cout << "Primero hay que cargar un CSV válido.\n";
        return;
    }

    int limite;
    std::cout << "\n--- FASE 1: RETRASO EN DESPEGUES ---\n";
    std::cout << "Introduce el umbral en minutos (positivo para retrasos, negativo para adelantos): ";
    std::cin >> limite;

    int total = static_cast<int>(datos.retraso_salida.size());
    std::size_t tamano_bytes = total * sizeof(float);

    //Contamos en CPU cuántos vuelos cumplen la condición para poder resumir la fase en el cloud
    int coincidencias = 0;
    for (int i = 0; i < total; i++) {
        float minutos = datos.retraso_salida[i];

        if (std::isnan(minutos)) {
            continue;
        }

        if ((limite >= 0 && minutos >= limite) ||
            (limite < 0 && minutos <= limite)) {
            coincidencias++;
        }
    }

    float* d_retrasos = nullptr;

    //Reservamos hueco en la VRAM de la gráfica
    cudaError_t error = cudaMalloc((void**)&d_retrasos, tamano_bytes);
    if (error != cudaSuccess) {
        std::cout << "Fallo al reservar memoria en GPU: " << cudaGetErrorString(error) << "\n";
        return;
    }

    //Mandamos el vector de C++ a la gráfica
    error = cudaMemcpy(d_retrasos, datos.retraso_salida.data(), tamano_bytes, cudaMemcpyHostToDevice);
    if (error != cudaSuccess) {
        std::cout << "Fallo al copiar los datos a la VRAM: " << cudaGetErrorString(error) << "\n";
        cudaFree(d_retrasos);
        return;
    }

    //Consultamos la gráfica para no meter hilos a piñón
    int hilos_bloque = elegir_hilos_por_bloque();
    int bloques_grid = calcular_num_bloques(total, hilos_bloque);

    std::cout << "Lanzando kernel con " << bloques_grid << " bloques y "
        << hilos_bloque << " hilos por bloque.\n";

    //Disparamos el kernel
    filtrar_despegues_gpu << <bloques_grid, hilos_bloque >> > (d_retrasos, total, limite);

    //Esperamos a que la GPU termine de imprimir todo
    error = cudaDeviceSynchronize();
    if (error != cudaSuccess) {
        std::cout << "Error en la ejecucion del kernel: " << cudaGetErrorString(error) << "\n";
    }
    else {
        std::cout << "Fase 1 completada con exito.\n";
        std::cout << "Total de coincidencias encontradas: " << coincidencias << "\n";
    }

    //Preparamos el registro para cloud
    RegistroCloud registro;
    registro.fase = "Fase 1";
    registro.fecha = obtener_fecha_actual();
    registro.parametros = "umbral=" + std::to_string(limite);
    registro.resultado = "coincidencias=" + std::to_string(coincidencias);

    if (preguntar_subida_cloud()) {
        registro.usuario = pedir_usuario_cloud();
        mostrar_registro_cloud(registro);
        //añadido
        // Llama a la función que creamos en cloud_envio.cpp
        enviar_registro_cloud(registro);
    }

    //Limpiamos la memoria para que no haya fugas
    cudaFree(d_retrasos);
}







#include <iostream>
#include <vector>
#include <cstring>
#include <cmath>
#include <cuda_runtime.h>

#include "fase2_aterrizajes.h"
#include "info_gpu.h"
#include "cloud_envio.h"

#define TOPE_MATRICULA 16

//Usamos memoria constante porque el umbral no cambia y así todos los hilos del warp lo leen a la vez de la caché de manera rápida
__constant__ int umbral_llegada;

//Función auxiliar en la GPU para copiar las matrículas letra a letra
__device__ void clonar_matricula(char* destino, const char* origen) {
    for (int i = 0; i < TOPE_MATRICULA; i++) {
        destino[i] = origen[i];
        if (origen[i] == '\0') {
            break; //Cortamos si llegamos al final del string
        }
    }
}

//Kernel principal de la Fase 2
__global__ void buscar_aterrizajes_gpu(
    const float* array_llegadas,
    const char* array_matriculas,
    int total_vuelos,
    int* contador_excesos,
    char* matriculas_pilladas,
    float* tiempos_pillados
) {
    //Calculamos qué vuelo le toca a este hilo
    int id_hilo = blockIdx.x * blockDim.x + threadIdx.x;

    if (id_hilo >= total_vuelos) {
        return;
    }

    float minutos = array_llegadas[id_hilo];

    //Saltamos los huecos vacíos del CSV
    if (isnan(minutos)) {
        return;
    }

    bool pillado = false;

    //Tiramos de la memoria constante para leer el umbral
    if ((umbral_llegada >= 0 && minutos >= umbral_llegada) ||
        (umbral_llegada < 0 && minutos <= umbral_llegada)) {
        pillado = true;
    }

    if (pillado) {
        //Usamos atomicAdd para poner en fila a los hilos ya que si no podrían pisarse al intentar sumar al contador a la vez
        //"pos" será el índice único donde este hilo guardará su avión
        int pos = atomicAdd(contador_excesos, 1);

        //Calculamos los punteros basándonos en nuestra posición única
        const char* mi_matricula_origen = &array_matriculas[id_hilo * TOPE_MATRICULA];
        char* mi_matricula_destino = &matriculas_pilladas[pos * TOPE_MATRICULA];

        clonar_matricula(mi_matricula_destino, mi_matricula_origen);
        tiempos_pillados[pos] = minutos;

        printf("Hilo global %d -> ARR_DELAY = %.2f, TAIL_NUM = %s\n",
            id_hilo, minutos, mi_matricula_origen);
    }
}

void lanzar_fase2(const DatosVuelos& datos) {
    if (datos.num_filas == 0) {
        std::cout << "Primero hay que cargar un CSV válido.\n";
        return;
    }

    int limite;
    std::cout << "\n--- FASE 2: RETRASO EN ATERRIZAJES ---\n";
    std::cout << "Introduce el umbral (minutos): ";
    std::cin >> limite;

    int total = static_cast<int>(datos.retraso_llegada.size());

    //Aplanamos las matrículas (strings de C++) en un array gigante de chars para que la GPU no colapse
    std::vector<char> matriculas_host(total * TOPE_MATRICULA, '\0');
    for (int i = 0; i < total; i++) {
        std::strncpy(&matriculas_host[i * TOPE_MATRICULA],
            datos.matricula_avion[i].c_str(),
            TOPE_MATRICULA - 1);
    }

    float* d_llegadas = nullptr;
    char* d_matriculas = nullptr;
    int* d_contador = nullptr;
    char* d_matriculas_salida = nullptr;
    float* d_tiempos_salida = nullptr;

    cudaError_t error;

    //Pasamos el umbral a la memoria constante
    error = cudaMemcpyToSymbol(umbral_llegada, &limite, sizeof(int));
    if (error != cudaSuccess) {
        std::cout << "Fallo al subir a memoria constante: " << cudaGetErrorString(error) << "\n";
        return;
    }

    //Reservas de memoria con control estricto de errores
    error = cudaMalloc((void**)&d_llegadas, total * sizeof(float));
    if (error != cudaSuccess) {
        std::cout << "Fallo al reservar memoria en GPU para los retrasos de llegada.\n";
        return;
    }

    error = cudaMalloc((void**)&d_matriculas, total * TOPE_MATRICULA * sizeof(char));
    if (error != cudaSuccess) {
        std::cout << "Fallo al reservar memoria para matriculas de origen.\n";
        cudaFree(d_llegadas);
        return;
    }

    error = cudaMalloc((void**)&d_contador, sizeof(int));
    if (error != cudaSuccess) {
        std::cout << "Error al reservar memoria para contador.\n";
        cudaFree(d_llegadas);
        cudaFree(d_matriculas);
        return;
    }

    // Reservamos salida con tamaño el tamaño total por si acaso todos los vuelos cumplen la condición
    error = cudaMalloc((void**)&d_matriculas_salida, total * TOPE_MATRICULA * sizeof(char));
    if (error != cudaSuccess) {
        std::cout << "Fallo al reservar memoria para matriculas de salida.\n";
        cudaFree(d_llegadas);
        cudaFree(d_matriculas);
        cudaFree(d_contador);
        return;
    }

    error = cudaMalloc((void**)&d_tiempos_salida, total * sizeof(float));
    if (error != cudaSuccess) {
        std::cout << "Error al reservar memoria para tiempos de salida.\n";
        cudaFree(d_llegadas);
        cudaFree(d_matriculas);
        cudaFree(d_contador);
        cudaFree(d_matriculas_salida);
        return;
    }

    //Ponemos el contador a 0 en la gráfica
    int cero = 0;
    cudaMemcpy(d_contador, &cero, sizeof(int), cudaMemcpyHostToDevice);

    //Transferencias Host a Device
    error = cudaMemcpy(d_llegadas, datos.retraso_llegada.data(), total * sizeof(float), cudaMemcpyHostToDevice);
    if (error != cudaSuccess) {
        std::cout << "Fallo pasando el array de llegadas a la grafica.\n";
        cudaFree(d_llegadas);
        cudaFree(d_matriculas);
        cudaFree(d_contador);
        cudaFree(d_matriculas_salida);
        cudaFree(d_tiempos_salida);
        return;
    }

    error = cudaMemcpy(d_matriculas, matriculas_host.data(), total * TOPE_MATRICULA * sizeof(char), cudaMemcpyHostToDevice);
    if (error != cudaSuccess) {
        std::cout << "Fallando pasando el array de matriculas a la grafica.\n";
        cudaFree(d_llegadas);
        cudaFree(d_matriculas);
        cudaFree(d_contador);
        cudaFree(d_matriculas_salida);
        cudaFree(d_tiempos_salida);
        return;
    }

    //Calculamos el hardware dinámicamente
    int hilos_bloque = elegir_hilos_por_bloque();
    int bloques_grid = calcular_num_bloques(total, hilos_bloque);

    std::cout << "Lanzando kernel con " << bloques_grid << " bloques y " << hilos_bloque << " hilos por bloque.\n";

    //Lanzamos el kernel
    buscar_aterrizajes_gpu << <bloques_grid, hilos_bloque >> > (
        d_llegadas,
        d_matriculas,
        total,
        d_contador,
        d_matriculas_salida,
        d_tiempos_salida
        );

    error = cudaDeviceSynchronize();
    if (error != cudaSuccess) {
        std::cout << "Error en la ejecucion del kernel: "
            << cudaGetErrorString(error) << "\n";
    }

    //Nos traemos cuántos aviones han entrado finalmente en el umbral
    int total_detectados = 0;
    cudaMemcpy(&total_detectados, d_contador, sizeof(int), cudaMemcpyDeviceToHost);

    std::cout << "Total de aviones detectados: " << total_detectados << "\n";

    //Si ha cogido a alguno, nos bajamos los resultados para enseñarlos
    if (total_detectados > 0) {
        std::vector<char> matriculas_salida_host(total_detectados * TOPE_MATRICULA, '\0');
        std::vector<float> tiempos_salida_host(total_detectados);

        cudaMemcpy(matriculas_salida_host.data(),
            d_matriculas_salida,
            total_detectados * TOPE_MATRICULA * sizeof(char),
            cudaMemcpyDeviceToHost);

        cudaMemcpy(tiempos_salida_host.data(),
            d_tiempos_salida,
            total_detectados * sizeof(float),
            cudaMemcpyDeviceToHost);

        std::cout << "Primeros resultados recuperados en CPU:\n";

        //Imprimimos un máximo de 10 para no colapsar la consola
        int mostrar = (total_detectados < 10) ? total_detectados : 10;

        for (int i = 0; i < mostrar; i++) {
            std::cout << "  [" << i << "] "
                << &matriculas_salida_host[i * TOPE_MATRICULA]
                << " -> " << tiempos_salida_host[i] << " min\n";
        }
    }

    //Preparamos el registro para cloud
    RegistroCloud registro;
    registro.fase = "Fase 2";
    registro.fecha = obtener_fecha_actual();
    registro.parametros = "umbral=" + std::to_string(limite);
    registro.resultado = "total_detectados=" + std::to_string(total_detectados);

    if (preguntar_subida_cloud()) {
        registro.usuario = pedir_usuario_cloud();
        mostrar_registro_cloud(registro);
    }

    //Liberemos la VRAM
    cudaFree(d_llegadas);
    cudaFree(d_matriculas);
    cudaFree(d_contador);
    cudaFree(d_matriculas_salida);
    cudaFree(d_tiempos_salida);
}

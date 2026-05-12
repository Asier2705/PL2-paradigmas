#include <iostream>
#include <vector>
#include <cmath>
#include <cuda_runtime.h>

#include "fase1_despegues.h"
#include "info_gpu.h"
#include "cloud_envio.h"

// Estructura auxiliar para almacenar temporalmente los resultados en memoria Host (CPU)
// antes de su serialización y envío a la nube.
struct CoincidenciaDespegue {
    int indice_vuelo;
    float dep_delay;
};

// Función interactiva: Otorga al usuario un control granular sobre la cantidad
// de peticiones HTTP que se realizarán a la API, evitando saturar la red.
int pedir_cantidad_subir_fase1(int total_disponibles) { 
    int cantidad;
    std::cout << "Hay " << total_disponibles
        << " coincidencias. Cuantas quieres subir al cloud? ";
    std::cin >> cantidad;

    // Validación de límites de entrada
    if (cantidad < 1) cantidad = 1;
    if (cantidad > total_disponibles) cantidad = total_disponibles;

    return cantidad;
}

// =========================================================================
// KERNEL CUDA: Evaluación paralela del umbral de despegue
// =========================================================================
__global__ void filtrar_despegues_gpu(const float* array_retrasos, int total_vuelos, int limite_minutos) {

    // Cálculo del identificador global del hilo (Grid 1D) para acceso coalescente a memoria
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

// =========================================================================
// FUNCIÓN PRINCIPAL DE FASE 1 (Host)
// =========================================================================
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

    // Almacenamos en CPU todas las coincidencias para procesar posteriormente
    // la selección interactiva de envío al entorno Cloud.
    std::vector<CoincidenciaDespegue> coincidencias_encontradas;
    coincidencias_encontradas.reserve(total);

    for (int i = 0; i < total; i++) {
        float minutos = datos.retraso_salida[i];

        if (std::isnan(minutos)) {
            continue;
        }

        if ((limite >= 0 && minutos >= limite) ||
            (limite < 0 && minutos <= limite)) {
            CoincidenciaDespegue c;
            c.indice_vuelo = i;
            c.dep_delay = minutos;
            coincidencias_encontradas.push_back(c);
        }
    }

    int coincidencias = static_cast<int>(coincidencias_encontradas.size());

    float* d_retrasos = nullptr;

    // 1. Reserva de memoria lineal en el Device (VRAM)
    cudaError_t error = cudaMalloc((void**)&d_retrasos, tamano_bytes);
    if (error != cudaSuccess) {
        std::cout << "Fallo al reservar memoria en GPU: " << cudaGetErrorString(error) << "\n";
        return;
    }

    // 2. Transferencia de datos Host-to-Device a través del bus PCIe
    error = cudaMemcpy(d_retrasos, datos.retraso_salida.data(), tamano_bytes, cudaMemcpyHostToDevice);
    if (error != cudaSuccess) {
        std::cout << "Fallo al copiar los datos a la VRAM: " << cudaGetErrorString(error) << "\n";
        cudaFree(d_retrasos);
        return;
    }

    // 3. Consulta dinámica del hardware para maximizar la ocupación
    int hilos_bloque = elegir_hilos_por_bloque();
    int bloques_grid = calcular_num_bloques(total, hilos_bloque);

    std::cout << "Lanzando kernel con " << bloques_grid << " bloques y "
        << hilos_bloque << " hilos por bloque.\n";

    // 4. Lanzamiento del Kernel asíncrono
    filtrar_despegues_gpu << <bloques_grid, hilos_bloque >> > (d_retrasos, total, limite);

    // 5. Barrera de sincronización: El Host espera a que la GPU finalice sus impresiones
    error = cudaDeviceSynchronize();
    if (error != cudaSuccess) {
        std::cout << "Error en la ejecucion del kernel: " << cudaGetErrorString(error) << "\n";
    }
    else {
        std::cout << "Fase 1 completada con exito.\n";
        std::cout << "Total de coincidencias encontradas: " << coincidencias << "\n";
    }

    // Liberación de recursos para evitar fugas de memoria (Memory Leaks) en la GPU
    cudaFree(d_retrasos);


    if (coincidencias == 0) {
        std::cout << "No hay coincidencias para subir al cloud.\n";
        return;
    }


    // =========================================================================
    // MÓDULO CLOUD: Interacción y Envío de Peticiones
    // =========================================================================

    if (preguntar_subida_cloud()) {
        std::string usuario = pedir_usuario_cloud();
        int cantidad_subir = pedir_cantidad_subir_fase1(coincidencias);

        int enviados_ok = 0;

        for (int i = 0; i < cantidad_subir; i++) {
            RegistroCloud registro;
            registro.usuario = usuario;
            registro.fase = "Fase 1";
            registro.fecha = obtener_fecha_actual();
            registro.parametros = "umbral=" + std::to_string(limite);

            // Empaquetado de los metadatos relevantes de la ejecución
            registro.resultado =
                "coincidencia=" + std::to_string(i + 1) + "/" + std::to_string(coincidencias) +
                ",indice_vuelo=" + std::to_string(coincidencias_encontradas[i].indice_vuelo) +
                ",DEP_DELAY=" + std::to_string(coincidencias_encontradas[i].dep_delay);

            bool enviado_ok = enviar_registro_cloud(registro);

            if (enviado_ok) {
                enviados_ok++;
            }
            else {
                // Implementación de resiliencia: Si la red falla, no se aborta el programa,
                // sino que se muestra el registro localmente como plan de contingencia.
                std::cout << "\nNo se pudo enviar esta coincidencia al cloud. Se muestra el registro localmente:\n";
                mostrar_registro_cloud(registro);
            }
        }

        std::cout << "\nResumen de subida: " << enviados_ok
            << " de " << cantidad_subir << " coincidencias enviadas correctamente.\n";
    }
}
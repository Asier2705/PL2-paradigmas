#include <iostream>
#include <vector>
#include <string>
#include <unordered_map>
#include <algorithm>
#include <iomanip>
#include <cuda_runtime.h>

#include "fase4_histograma.h"
#include "info_gpu.h"
#include "cloud_envio.h"

// =========================================================================
// ESTRUCTURA AUXILIAR PARA RESULTADOS DEL HISTOGRAMA
// =========================================================================

// Estructura auxiliar para almacenar cada aeropuerto que supera el umbral.
// Guarda el índice denso interno usado por la GPU y el número de ocurrencias
// detectadas en el histograma.
struct ResultadoHistograma {
    int indice;
    int ocurrencias;
};

// Función interactiva: permite al usuario decidir cuántos resultados quiere
// subir al Cloud, evitando enviar demasiadas peticiones HTTP innecesarias.
int pedir_cantidad_subir_fase4(int total_disponibles) {
    int cantidad;
    std::cout << "Hay " << total_disponibles
        << " aeropuertos que cumplen el umbral. Cuantos quieres subir al cloud? ";
    std::cin >> cantidad;

    if (cantidad < 1) cantidad = 1;
    if (cantidad > total_disponibles) cantidad = total_disponibles;

    return cantidad;
}


// =========================================================================
// KERNEL CUDA: Histograma usando memoria global
// =========================================================================

// Kernel que calcula el histograma usando únicamente memoria global.
// Cada hilo recorre parte del array de categorías y actualiza el contador
// correspondiente mediante atomicAdd.
__global__ void calcular_histograma_global(
    const int* array_categorias,
    int total_elementos,
    int* histograma_salida
) {
    // Identificador global del hilo dentro de un Grid 1D
    int id_hilo = blockIdx.x * blockDim.x + threadIdx.x;

    // Salto total entre iteraciones para que todos los hilos puedan recorrer
    // el array completo en caso de que haya más elementos que hilos.
    int salto = blockDim.x * gridDim.x;

    for (int i = id_hilo; i < total_elementos; i += salto) {
        int id_categoria = array_categorias[i];
        if (id_categoria >= 0) {
            atomicAdd(&histograma_salida[id_categoria], 1);
        }
    }
}

// =========================================================================
// KERNEL CUDA: Histograma optimizado con memoria compartida
// =========================================================================

//Calculo del histograma optimizado mediante el uso de memoria compartida
__global__ void calcular_histograma_compartido(
    const int* array_categorias,
    int total_elementos,
    int* histograma_global,
    int total_categorias_unicas
) {
    extern __shared__ int mem_compartida[];

    int hilo_local = threadIdx.x;

    for (int i = hilo_local; i < total_categorias_unicas; i += blockDim.x) {
        mem_compartida[i] = 0;
    }

    __syncthreads();

    int id_hilo = blockIdx.x * blockDim.x + hilo_local;
    int salto = blockDim.x * gridDim.x;

    for (int i = id_hilo; i < total_elementos; i += salto) {
        int id_categoria = array_categorias[i];
        if (id_categoria >= 0) {
            atomicAdd(&mem_compartida[id_categoria], 1);
        }
    }

    __syncthreads();

    for (int i = hilo_local; i < total_categorias_unicas; i += blockDim.x) {
        if (mem_compartida[i] > 0) {
            atomicAdd(&histograma_global[i], mem_compartida[i]);
        }
    }
}

// =========================================================================
// FUNCIÓN PRINCIPAL DE FASE 4 (Host)
// =========================================================================

void lanzar_fase4(const DatosVuelos& datos) {
    if (datos.num_filas == 0) {
        std::cout << "No hay datos cargados en el sistema\n";
        return;
    }

    int opcion_tipo;
    int umbral_minimo;

    // =========================================================================
    // MENÚ INTERACTIVO
    // =========================================================================

    std::cout << "\n--- FASE 4: HISTOGRAMA DE AEROPUERTOS ---\n";
    std::cout << "Seleccione la clasificacion del aeropuerto:\n";
    std::cout << "1. Origen\n";
    std::cout << "2. Destino\n";
    std::cout << "Opcion: ";
    std::cin >> opcion_tipo;

    std::cout << "Introduzca el umbral minimo de ocurrencias para la visualizacion: ";
    std::cin >> umbral_minimo;

    const std::vector<int>* ids_base = nullptr;
    const std::vector<std::string>* codigos_base = nullptr;
    const char* etiqueta_tipo = "";

    // =========================================================================
    // SELECCIÓN DEL CONJUNTO DE DATOS
    // =========================================================================

    if (opcion_tipo == 1) {
        ids_base = &datos.id_aeropuerto_origen;
        codigos_base = &datos.aeropuerto_origen;
        etiqueta_tipo = "Origen";
    }
    else if (opcion_tipo == 2) {
        ids_base = &datos.id_aeropuerto_destino;
        codigos_base = &datos.aeropuerto_destino;
        etiqueta_tipo = "Destino";
    }
    else {
        std::cout << "Seleccion de aeropuerto invalida\n";
        return;
    }

    int total_registros = static_cast<int>(ids_base->size());

    // =========================================================================
    // PREPROCESADO HOST: Compresión de IDs reales a índices densos
    // =========================================================================

    std::unordered_map<int, int> mapa_id_a_denso;
    std::unordered_map<int, std::string> mapa_id_a_codigo;
    std::vector<int> registro_ids_unicos;
    std::vector<std::string> registro_codigos_unicos;

    for (int i = 0; i < total_registros; i++) {
        int id_real = (*ids_base)[i];

        if (id_real < 0) {
            continue;
        }

        auto iterador = mapa_id_a_denso.find(id_real);
        if (iterador == mapa_id_a_denso.end()) {
            int indice_asignado = static_cast<int>(registro_ids_unicos.size());
            mapa_id_a_denso[id_real] = indice_asignado;
            registro_ids_unicos.push_back(id_real);

            std::string codigo_str = (*codigos_base)[i];
            if (codigo_str.empty()) {
                codigo_str = "UNK";
            }

            registro_codigos_unicos.push_back(codigo_str);
            mapa_id_a_codigo[id_real] = codigo_str;
        }
    }

    int total_categorias = static_cast<int>(registro_ids_unicos.size());

    if (total_categorias == 0) {
        std::cout << "No se han detectado aeropuertos validos en el conjunto de datos\n";
        return;
    }

    // =========================================================================
    // CONSTRUCCIÓN DEL ARRAY DE CATEGORÍAS DENSAS
    // =========================================================================

    std::vector<int> vector_categorias_densas(total_registros, -1);

    for (int i = 0; i < total_registros; i++) {
        int id_real = (*ids_base)[i];

        if (id_real < 0) {
            vector_categorias_densas[i] = -1;
        }
        else {
            vector_categorias_densas[i] = mapa_id_a_denso[id_real];
        }
    }

    // =========================================================================
    // RESERVA DE MEMORIA EN DEVICE
    // =========================================================================

    int* d_array_categorias = nullptr;
    int* d_array_histograma = nullptr;
    cudaError_t estado_memoria;

    estado_memoria = cudaMalloc((void**)&d_array_categorias, total_registros * sizeof(int));
    if (estado_memoria != cudaSuccess) {
        std::cout << "Fallo en la reserva de memoria para las categorias: " << cudaGetErrorString(estado_memoria) << "\n";
        return;
    }

    estado_memoria = cudaMalloc((void**)&d_array_histograma, total_categorias * sizeof(int));
    if (estado_memoria != cudaSuccess) {
        std::cout << "Fallo en la reserva de memoria para el histograma: " << cudaGetErrorString(estado_memoria) << "\n";
        cudaFree(d_array_categorias);
        return;
    }


    // =========================================================================
    // TRANSFERENCIAS HOST-TO-DEVICE
    // =========================================================================
    estado_memoria = cudaMemcpy(d_array_categorias, vector_categorias_densas.data(), total_registros * sizeof(int), cudaMemcpyHostToDevice);
    if (estado_memoria != cudaSuccess) {
        std::cout << "Error durante la transferencia de categorias a la GPU: " << cudaGetErrorString(estado_memoria) << "\n";
        cudaFree(d_array_categorias);
        cudaFree(d_array_histograma);
        return;
    }

    estado_memoria = cudaMemset(d_array_histograma, 0, total_categorias * sizeof(int));
    if (estado_memoria != cudaSuccess) {
        std::cout << "Fallo al inicializar el array de histograma en la GPU: " << cudaGetErrorString(estado_memoria) << "\n";
        cudaFree(d_array_categorias);
        cudaFree(d_array_histograma);
        return;
    }


    // =========================================================================
    // CONFIGURACIÓN DE EJECUCIÓN CUDA
    // =========================================================================

    int hilos_bloque = elegir_hilos_por_bloque();
    int bloques_grid = calcular_num_bloques(total_registros, hilos_bloque);

    cudaDeviceProp propiedades_dispositivo;
    cudaGetDeviceProperties(&propiedades_dispositivo, 0);

    std::size_t memoria_dinamica_requerida = total_categorias * sizeof(int);
    bool capacidad_suficiente = memoria_dinamica_requerida <= propiedades_dispositivo.sharedMemPerBlock;

    std::cout << "Analisis de clasificacion: " << etiqueta_tipo << "\n";
    std::cout << "Categorias unicas extraidas: " << total_categorias << "\n";
    std::cout << "Configuracion de lanzamiento: " << bloques_grid << " bloques y " << hilos_bloque << " hilos/bloque\n";

    // =========================================================================
    // LANZAMIENTO DEL KERNEL
    // =========================================================================
    if (capacidad_suficiente) {
        std::cout << "Modo operativo: Memoria compartida activada\n";
        calcular_histograma_compartido << <bloques_grid, hilos_bloque, memoria_dinamica_requerida >> > (
            d_array_categorias,
            total_registros,
            d_array_histograma,
            total_categorias
            );
    }
    else {
        std::cout << "Modo operativo: Memoria global (limite de shared cache excedido)\n";
        calcular_histograma_global << <bloques_grid, hilos_bloque >> > (
            d_array_categorias,
            total_registros,
            d_array_histograma
            );
    }

    estado_memoria = cudaDeviceSynchronize();
    if (estado_memoria != cudaSuccess) {
        std::cout << "Error critico durante la ejecucion del kernel: " << cudaGetErrorString(estado_memoria) << "\n";
        cudaFree(d_array_categorias);
        cudaFree(d_array_histograma);
        return;
    }

    // =========================================================================
    // RECUPERACIÓN DEL HISTOGRAMA DEVICE-TO-HOST
    // =========================================================================
    std::vector<int> histograma_final_cpu(total_categorias);
    estado_memoria = cudaMemcpy(histograma_final_cpu.data(), d_array_histograma, total_categorias * sizeof(int), cudaMemcpyDeviceToHost);
    if (estado_memoria != cudaSuccess) {
        std::cout << "Fallo al extraer el histograma al procesador: " << cudaGetErrorString(estado_memoria) << "\n";
        cudaFree(d_array_categorias);
        cudaFree(d_array_histograma);
        return;
    }


    // =========================================================================
    // FILTRADO Y ORDENACIÓN DE RESULTADOS EN CPU
    // =========================================================================

    std::vector<ResultadoHistograma> coleccion_filtrada;
    coleccion_filtrada.reserve(total_categorias);

    for (int i = 0; i < total_categorias; i++) {
        if (histograma_final_cpu[i] >= umbral_minimo) {
            ResultadoHistograma nodo;
            nodo.indice = i;
            nodo.ocurrencias = histograma_final_cpu[i];
            coleccion_filtrada.push_back(nodo);
        }
    }

    std::sort(
        coleccion_filtrada.begin(),
        coleccion_filtrada.end(),
        [](const ResultadoHistograma& a, const ResultadoHistograma& b) {
            return a.ocurrencias > b.ocurrencias;
        }
    );

    // =========================================================================
    // IMPRESIÓN DE RESULTADOS
    // =========================================================================
    std::cout << "\nResultados consolidados de la Fase 4:\n";
    std::cout << "Total de aeropuertos clasificados: " << total_categorias << "\n";
    std::cout << "Aeropuertos que superan el umbral establecido: " << coleccion_filtrada.size() << "\n\n";

    if (coleccion_filtrada.empty()) {
        std::cout << "Ningun aeropuerto cumple con el criterio de ocurrencias especificado\n";
    }
    else {
        int maximas_ocurrencias = coleccion_filtrada[0].ocurrencias;
        const int longitud_maxima_barra = 50;

        std::cout << "Representacion grafica:\n";
        for (const auto& elemento : coleccion_filtrada) {
            const std::string& codigo_str = registro_codigos_unicos[elemento.indice];

            int representacion_barras = 0;
            if (maximas_ocurrencias > 0) {
                representacion_barras = (elemento.ocurrencias * longitud_maxima_barra) / maximas_ocurrencias;
            }
            if (representacion_barras == 0) {
                representacion_barras = 1;
            }

            std::cout << std::setw(6) << codigo_str << " | "
                << std::string(representacion_barras, '#')
                << " (" << elemento.ocurrencias << ")\n";
        }
    }

    // =========================================================================
    // LIBERACIÓN DE RECURSOS GPU
    // =========================================================================

    //Liberacion segura de las reservas en la VRAM
    cudaFree(d_array_categorias);
    cudaFree(d_array_histograma);

    if (coleccion_filtrada.empty()) {
        std::cout << "No hay resultados para subir al cloud.\n";
        return;
    }

    // =========================================================================
    // MÓDULO CLOUD: Interacción y envío de peticiones
    // =========================================================================

    if (preguntar_subida_cloud()) {
        std::string usuario = pedir_usuario_cloud();
        int cantidad_subir = pedir_cantidad_subir_fase4(static_cast<int>(coleccion_filtrada.size()));

        int enviados_ok = 0;

        for (int i = 0; i < cantidad_subir; i++) {
            const auto& elemento = coleccion_filtrada[i];
            const std::string& codigo_str = registro_codigos_unicos[elemento.indice];

            RegistroCloud registro;
            registro.usuario = usuario;
            registro.fase = "Fase 4";
            registro.fecha = obtener_fecha_actual();

            // Parámetros generales de la ejecución
            registro.parametros = std::string("tipo=") + etiqueta_tipo +
                ",umbral=" + std::to_string(umbral_minimo);

            // Empaquetado del resultado concreto que se va a subir al Cloud.
            // Se incluye la posición en el ranking, el código del aeropuerto
            // y el número de ocurrencias detectadas.
            registro.resultado =
                "top=" + std::to_string(i + 1) + "/" + std::to_string(coleccion_filtrada.size()) +
                ",aeropuerto=" + codigo_str +
                ",ocurrencias=" + std::to_string(elemento.ocurrencias);

            bool enviado_ok = enviar_registro_cloud(registro);

            if (enviado_ok) {
                enviados_ok++;
            }
            else {
                // Si falla el envío al Cloud, no se pierde el resultado.
                // Se muestra localmente como mecanismo de contingencia.
                std::cout << "\nNo se pudo enviar este aeropuerto al cloud. Se muestra el registro localmente:\n";
                mostrar_registro_cloud(registro);
            }
        }

        std::cout << "\nResumen de subida: " << enviados_ok
            << " de " << cantidad_subir << " resultados enviados correctamente.\n";
    }
}

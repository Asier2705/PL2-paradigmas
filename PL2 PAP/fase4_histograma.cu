#include <iostream>
#include <vector>
#include <string>
#include <unordered_map>
#include <algorithm>
#include <iomanip>
#include <cuda_runtime.h>

#include "fase4_histograma.h"
#include "info_gpu.h"

//Estructura auxiliar para agrupar y ordenar los resultados finales
struct ResultadoHistograma {
    int indice;
    int ocurrencias;
};

//Calculo del histograma usando unicamente la memoria global como mecanismo de seguridad
__global__ void calcular_histograma_global(
    const int* array_categorias,
    int total_elementos,
    int* histograma_salida
) {
    //Calculo del identificador global y el salto para el grid stride loop
    int id_hilo = blockIdx.x * blockDim.x + threadIdx.x;
    int salto = blockDim.x * gridDim.x;

    for (int i = id_hilo; i < total_elementos; i += salto) {
        int id_categoria = array_categorias[i];
        if (id_categoria >= 0) {
            atomicAdd(&histograma_salida[id_categoria], 1);
        }
    }
}

//Calculo del histograma optimizado mediante el uso de memoria compartida
__global__ void calcular_histograma_compartido(
    const int* array_categorias,
    int total_elementos,
    int* histograma_global,
    int total_categorias_unicas
) {
    extern __shared__ int mem_compartida[];

    int hilo_local = threadIdx.x;

    //Inicializacion a cero de la memoria compartida asignada a este bloque
    for (int i = hilo_local; i < total_categorias_unicas; i += blockDim.x) {
        mem_compartida[i] = 0;
    }

    //Sincronizacion obligatoria para asegurar que la memoria esta limpia antes del computo
    __syncthreads();

    int id_hilo = blockIdx.x * blockDim.x + hilo_local;
    int salto = blockDim.x * gridDim.x;

    //Conteo local utilizando operaciones atomicas sobre la memoria de alta velocidad
    for (int i = id_hilo; i < total_elementos; i += salto) {
        int id_categoria = array_categorias[i];
        if (id_categoria >= 0) {
            atomicAdd(&mem_compartida[id_categoria], 1);
        }
    }

    //Sincronizacion para garantizar que todos los hilos han terminado el conteo local
    __syncthreads();

    //Volcado final de los resultados parciales hacia la memoria global
    for (int i = hilo_local; i < total_categorias_unicas; i += blockDim.x) {
        if (mem_compartida[i] > 0) {
            atomicAdd(&histograma_global[i], mem_compartida[i]);
        }
    }
}

void lanzar_fase4(const DatosVuelos& datos) {
    //Validacion inicial para evitar procesamiento sobre estructuras vacias
    if (datos.num_filas == 0) {
        std::cout << "No hay datos cargados en el sistema\n";
        return;
    }

    int opcion_tipo;
    int umbral_minimo;

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

    //Diccionarios de la CPU para mapear los IDs reales dispersos a indices densos secuenciales
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

    //Transformacion del vector original a categorias densas aptas para el calculo en GPU
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

    int* d_array_categorias = nullptr;
    int* d_array_histograma = nullptr;
    cudaError_t estado_memoria;

    //Reserva de memoria en el dispositivo con gestion de errores
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

    //Transferencia de los datos procesados al dispositivo
    estado_memoria = cudaMemcpy(d_array_categorias, vector_categorias_densas.data(), total_registros * sizeof(int), cudaMemcpyHostToDevice);
    if (estado_memoria != cudaSuccess) {
        std::cout << "Error durante la transferencia de categorias a la GPU: " << cudaGetErrorString(estado_memoria) << "\n";
        cudaFree(d_array_categorias);
        cudaFree(d_array_histograma);
        return;
    }

    //Inicializacion del espacio de resultados a cero directamente en la VRAM
    estado_memoria = cudaMemset(d_array_histograma, 0, total_categorias * sizeof(int));
    if (estado_memoria != cudaSuccess) {
        std::cout << "Fallo al inicializar el array de histograma en la GPU: " << cudaGetErrorString(estado_memoria) << "\n";
        cudaFree(d_array_categorias);
        cudaFree(d_array_histograma);
        return;
    }

    int hilos_bloque = elegir_hilos_por_bloque();
    int bloques_grid = calcular_num_bloques(total_registros, hilos_bloque);

    //Consulta de la arquitectura fisica para determinar la viabilidad de usar memoria compartida
    cudaDeviceProp propiedades_dispositivo;
    cudaGetDeviceProperties(&propiedades_dispositivo, 0);

    std::size_t memoria_dinamica_requerida = total_categorias * sizeof(int);
    bool capacidad_suficiente = memoria_dinamica_requerida <= propiedades_dispositivo.sharedMemPerBlock;

    std::cout << "Analisis de clasificacion: " << etiqueta_tipo << "\n";
    std::cout << "Categorias unicas extraidas: " << total_categorias << "\n";
    std::cout << "Configuracion de lanzamiento: " << bloques_grid << " bloques y " << hilos_bloque << " hilos/bloque\n";

    //Bifurcacion dinamica del flujo de ejecucion segun las limitaciones fisicas del hardware
    if (capacidad_suficiente) {
        std::cout << "Modo operativo: Memoria compartida activada\n";
        calcular_histograma_compartido <<<bloques_grid, hilos_bloque, memoria_dinamica_requerida >>> (
            d_array_categorias,
            total_registros,
            d_array_histograma,
            total_categorias
            );
    }
    else {
        std::cout << "Modo operativo: Memoria global (limite de shared cache excedido)\n";
        calcular_histograma_global <<<bloques_grid, hilos_bloque >>> (
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

    //Recuperacion del vector de frecuencias resultante
    std::vector<int> histograma_final_cpu(total_categorias);
    estado_memoria = cudaMemcpy(histograma_final_cpu.data(), d_array_histograma, total_categorias * sizeof(int), cudaMemcpyDeviceToHost);
    if (estado_memoria != cudaSuccess) {
        std::cout << "Fallo al extraer el histograma al procesador: " << cudaGetErrorString(estado_memoria) << "\n";
        cudaFree(d_array_categorias);
        cudaFree(d_array_histograma);
        return;
    }

    //Filtrado de registros aplicando el limite establecido por el usuario
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

    //Ordenacion estructural basandose en el mayor numero de ocurrencias
    std::sort(
        coleccion_filtrada.begin(),
        coleccion_filtrada.end(),
        [](const ResultadoHistograma& a, const ResultadoHistograma& b) {
            return a.ocurrencias > b.ocurrencias;
        }
    );

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
                //Escalado proporcional de la representacion visual respecto al valor maximo absoluto
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

    //Liberacion segura de las reservas en la VRAM
    cudaFree(d_array_categorias);
    cudaFree(d_array_histograma);
}
#include <iostream>
#include <vector>
#include <cmath>
#include <climits>
#include <cuda_runtime.h>

#include "fase3_reduccion.h"
#include "info_gpu.h"
#include "cloud_envio.h"

//Funciones propias para GPU porque std::max y std::min a veces dan problemas en CUDA
__device__ int saca_max(int a, int b) {
    return (a > b) ? a : b;
}

__device__ int saca_min(int a, int b) {
    return (a < b) ? a : b;
}

// ==========================================
// 3.1 SIMPLE (Fuerza Bruta)
// ==========================================

__global__ void reduccion_fuerza_bruta_max(const int* array_datos, int total_vuelos, int* resultado_final) {
    int id_global = blockIdx.x * blockDim.x + threadIdx.x;
    if (id_global >= total_vuelos) return;

    int valor = array_datos[id_global];
    if (valor == INT_MIN) return;

    atomicMax(resultado_final, valor);
}

__global__ void reduccion_fuerza_bruta_min(const int* array_datos, int total_vuelos, int* resultado_final) {
    int id_global = blockIdx.x * blockDim.x + threadIdx.x;
    if (id_global >= total_vuelos) return;

    int valor = array_datos[id_global];
    if (valor == INT_MAX) return;

    atomicMin(resultado_final, valor);
}

// ==========================================
// 3.2 BASICA (Memoria Compartida y Vecinos)
// ==========================================

__global__ void reduccion_vecinos_max(const int* array_datos, int total_vuelos, int* resultado_final) {
    extern __shared__ int mem_compartida[];

    int hilo_local = threadIdx.x;
    int id_global = blockIdx.x * blockDim.x + hilo_local;

    if (id_global < total_vuelos) mem_compartida[hilo_local] = array_datos[id_global];
    else mem_compartida[hilo_local] = INT_MIN;

    __syncthreads();

    if (id_global >= total_vuelos) return;

    int actual = mem_compartida[hilo_local];
    int anterior = (hilo_local == 0) ? ((id_global > 0) ? array_datos[id_global - 1] : INT_MIN) : mem_compartida[hilo_local - 1];
    int posterior = (hilo_local == blockDim.x - 1 || id_global == total_vuelos - 1)
        ? ((id_global < total_vuelos - 1) ? array_datos[id_global + 1] : INT_MIN)
        : mem_compartida[hilo_local + 1];

    int maximo_local = saca_max(saca_max(actual, anterior), posterior);
    if (maximo_local != INT_MIN) atomicMax(resultado_final, maximo_local);
}

__global__ void reduccion_vecinos_min(const int* array_datos, int total_vuelos, int* resultado_final) {
    extern __shared__ int mem_compartida[];

    int hilo_local = threadIdx.x;
    int id_global = blockIdx.x * blockDim.x + hilo_local;

    if (id_global < total_vuelos) mem_compartida[hilo_local] = array_datos[id_global];
    else mem_compartida[hilo_local] = INT_MAX;

    __syncthreads();

    if (id_global >= total_vuelos) return;

    int actual = mem_compartida[hilo_local];
    int anterior = (hilo_local == 0) ? ((id_global > 0) ? array_datos[id_global - 1] : INT_MAX) : mem_compartida[hilo_local - 1];
    int posterior = (hilo_local == blockDim.x - 1 || id_global == total_vuelos - 1)
        ? ((id_global < total_vuelos - 1) ? array_datos[id_global + 1] : INT_MAX)
        : mem_compartida[hilo_local + 1];

    int minimo_local = saca_min(saca_min(actual, anterior), posterior);
    if (minimo_local != INT_MAX) atomicMin(resultado_final, minimo_local);
}

// ==========================================
// 3.3 INTERMEDIA (Optimización Par/Impar)
// ==========================================

__global__ void reduccion_pares_max(const int* array_datos, int total_vuelos, int* resultado_final) {
    extern __shared__ int mem_compartida[];

    int hilo_local = threadIdx.x;
    int id_global = blockIdx.x * blockDim.x + hilo_local;

    if (id_global < total_vuelos) mem_compartida[hilo_local] = array_datos[id_global];
    else mem_compartida[hilo_local] = INT_MIN;

    __syncthreads();

    if (id_global >= total_vuelos) return;

    int actual = mem_compartida[hilo_local];
    int anterior = (hilo_local == 0) ? ((id_global > 0) ? array_datos[id_global - 1] : INT_MIN) : mem_compartida[hilo_local - 1];
    int posterior = (hilo_local == blockDim.x - 1 || id_global == total_vuelos - 1)
        ? ((id_global < total_vuelos - 1) ? array_datos[id_global + 1] : INT_MIN)
        : mem_compartida[hilo_local + 1];

    mem_compartida[hilo_local] = saca_max(saca_max(actual, anterior), posterior);

    __syncthreads();

    if (hilo_local % 2 == 0) {
        int vecino_impar = (hilo_local + 1 < blockDim.x && id_global + 1 < total_vuelos) ? mem_compartida[hilo_local + 1] : INT_MIN;
        int ganador_pareja = saca_max(mem_compartida[hilo_local], vecino_impar);
        if (ganador_pareja != INT_MIN) atomicMax(resultado_final, ganador_pareja);
    }
}

__global__ void reduccion_pares_min(const int* array_datos, int total_vuelos, int* resultado_final) {
    extern __shared__ int mem_compartida[];

    int hilo_local = threadIdx.x;
    int id_global = blockIdx.x * blockDim.x + hilo_local;

    if (id_global < total_vuelos) mem_compartida[hilo_local] = array_datos[id_global];
    else mem_compartida[hilo_local] = INT_MAX;

    __syncthreads();

    if (id_global >= total_vuelos) return;

    int actual = mem_compartida[hilo_local];
    int anterior = (hilo_local == 0) ? ((id_global > 0) ? array_datos[id_global - 1] : INT_MAX) : mem_compartida[hilo_local - 1];
    int posterior = (hilo_local == blockDim.x - 1 || id_global == total_vuelos - 1)
        ? ((id_global < total_vuelos - 1) ? array_datos[id_global + 1] : INT_MAX)
        : mem_compartida[hilo_local + 1];

    mem_compartida[hilo_local] = saca_min(saca_min(actual, anterior), posterior);

    __syncthreads();

    if (hilo_local % 2 == 0) {
        int vecino_impar = (hilo_local + 1 < blockDim.x && id_global + 1 < total_vuelos) ? mem_compartida[hilo_local + 1] : INT_MAX;
        int ganador_pareja = saca_min(mem_compartida[hilo_local], vecino_impar);
        if (ganador_pareja != INT_MAX) atomicMin(resultado_final, ganador_pareja);
    }
}

// ==============================================
// 3.4 PATRON DE REDUCCION (El Árbol)
// ==============================================

__global__ void reduccion_arbol_max(const int* entrada, int total_vuelos, int* salida_bloque) {
    extern __shared__ int mem_compartida[];

    int hilo_local = threadIdx.x;
    int inicio = blockIdx.x * blockDim.x * 2;
    int i = inicio + hilo_local;

    int valor = INT_MIN;

    if (i < total_vuelos) valor = entrada[i];
    if (i + blockDim.x < total_vuelos) valor = saca_max(valor, entrada[i + blockDim.x]);

    mem_compartida[hilo_local] = valor;
    __syncthreads();

    for (int salto = blockDim.x / 2; salto > 0; salto >>= 1) {
        if (hilo_local < salto) {
            mem_compartida[hilo_local] = saca_max(mem_compartida[hilo_local], mem_compartida[hilo_local + salto]);
        }
        __syncthreads();
    }

    if (hilo_local == 0) {
        salida_bloque[blockIdx.x] = mem_compartida[0];
    }
}

__global__ void reduccion_arbol_min(const int* entrada, int total_vuelos, int* salida_bloque) {
    extern __shared__ int mem_compartida[];

    int hilo_local = threadIdx.x;
    int inicio = blockIdx.x * blockDim.x * 2;
    int i = inicio + hilo_local;

    int valor = INT_MAX;

    if (i < total_vuelos) valor = entrada[i];
    if (i + blockDim.x < total_vuelos) valor = saca_min(valor, entrada[i + blockDim.x]);

    mem_compartida[hilo_local] = valor;
    __syncthreads();

    for (int salto = blockDim.x / 2; salto > 0; salto >>= 1) {
        if (hilo_local < salto) {
            mem_compartida[hilo_local] = saca_min(mem_compartida[hilo_local], mem_compartida[hilo_local + salto]);
        }
        __syncthreads();
    }

    if (hilo_local == 0) {
        salida_bloque[blockIdx.x] = mem_compartida[0];
    }
}

// ==========================================
// FUNCIONES DE LANZAMIENTO HOST
// ==========================================

bool test_variante_1_simple(const int* d_datos, int total, bool es_maximo,
    int hilos, int bloques, int& res_final) {
    int* d_res = nullptr;
    cudaError_t error = cudaMalloc((void**)&d_res, sizeof(int));
    if (error != cudaSuccess) return false;

    int inicio = es_maximo ? INT_MIN : INT_MAX;
    cudaMemcpy(d_res, &inicio, sizeof(int), cudaMemcpyHostToDevice);

    if (es_maximo)
        reduccion_fuerza_bruta_max << <bloques, hilos >> > (d_datos, total, d_res);
    else
        reduccion_fuerza_bruta_min << <bloques, hilos >> > (d_datos, total, d_res);

    error = cudaDeviceSynchronize();
    if (error != cudaSuccess) {
        cudaFree(d_res);
        return false;
    }

    error = cudaMemcpy(&res_final, d_res, sizeof(int), cudaMemcpyDeviceToHost);
    cudaFree(d_res);
    return error == cudaSuccess;
}

bool test_variante_2_basica(const int* d_datos, int total, bool es_maximo,
    int hilos, int bloques, std::size_t memoria_dinamica, int& res_final) {
    int* d_res = nullptr;
    cudaError_t error = cudaMalloc((void**)&d_res, sizeof(int));
    if (error != cudaSuccess) return false;

    int inicio = es_maximo ? INT_MIN : INT_MAX;
    cudaMemcpy(d_res, &inicio, sizeof(int), cudaMemcpyHostToDevice);

    if (es_maximo)
        reduccion_vecinos_max << <bloques, hilos, memoria_dinamica >> > (d_datos, total, d_res);
    else
        reduccion_vecinos_min << <bloques, hilos, memoria_dinamica >> > (d_datos, total, d_res);

    error = cudaDeviceSynchronize();
    if (error != cudaSuccess) {
        cudaFree(d_res);
        return false;
    }

    error = cudaMemcpy(&res_final, d_res, sizeof(int), cudaMemcpyDeviceToHost);
    cudaFree(d_res);
    return error == cudaSuccess;
}

bool test_variante_3_intermedia(const int* d_datos, int total, bool es_maximo,
    int hilos, int bloques, std::size_t memoria_dinamica, int& res_final) {
    int* d_res = nullptr;
    cudaError_t error = cudaMalloc((void**)&d_res, sizeof(int));
    if (error != cudaSuccess) return false;

    int inicio = es_maximo ? INT_MIN : INT_MAX;
    cudaMemcpy(d_res, &inicio, sizeof(int), cudaMemcpyHostToDevice);

    if (es_maximo)
        reduccion_pares_max << <bloques, hilos, memoria_dinamica >> > (d_datos, total, d_res);
    else
        reduccion_pares_min << <bloques, hilos, memoria_dinamica >> > (d_datos, total, d_res);

    error = cudaDeviceSynchronize();
    if (error != cudaSuccess) {
        cudaFree(d_res);
        return false;
    }

    error = cudaMemcpy(&res_final, d_res, sizeof(int), cudaMemcpyDeviceToHost);
    cudaFree(d_res);
    return error == cudaSuccess;
}

bool test_variante_4_arbol(const int* d_datos, int total, bool es_maximo,
    int hilos, std::size_t memoria_dinamica, int& res_final) {

    int* puntero_bucle = const_cast<int*>(d_datos);
    int tope_bucle = total;
    bool toca_liberar = false;

    while (tope_bucle > 10) {
        int nuevos_bloques = (tope_bucle + (hilos * 2 - 1)) / (hilos * 2);
        int* buffer_parcial = nullptr;

        cudaError_t error = cudaMalloc((void**)&buffer_parcial, nuevos_bloques * sizeof(int));
        if (error != cudaSuccess) {
            if (toca_liberar) cudaFree(puntero_bucle);
            return false;
        }

        if (es_maximo)
            reduccion_arbol_max << <nuevos_bloques, hilos, memoria_dinamica >> > (puntero_bucle, tope_bucle, buffer_parcial);
        else
            reduccion_arbol_min << <nuevos_bloques, hilos, memoria_dinamica >> > (puntero_bucle, tope_bucle, buffer_parcial);

        error = cudaDeviceSynchronize();
        if (error != cudaSuccess) {
            cudaFree(buffer_parcial);
            if (toca_liberar) cudaFree(puntero_bucle);
            return false;
        }

        if (toca_liberar) cudaFree(puntero_bucle);

        puntero_bucle = buffer_parcial;
        tope_bucle = nuevos_bloques;
        toca_liberar = true;
    }

    std::vector<int> array_final_host(tope_bucle);
    cudaError_t error = cudaMemcpy(array_final_host.data(), puntero_bucle, tope_bucle * sizeof(int), cudaMemcpyDeviceToHost);

    if (toca_liberar) cudaFree(puntero_bucle);
    if (error != cudaSuccess || tope_bucle <= 0) return false;

    res_final = array_final_host[0];
    for (int i = 1; i < tope_bucle; i++) {
        if (es_maximo) {
            res_final = (res_final > array_final_host[i]) ? res_final : array_final_host[i];
        }
        else {
            res_final = (res_final < array_final_host[i]) ? res_final : array_final_host[i];
        }
    }

    return true;
}

// ====================================
// FASE 3: MENU Y PREPARATIVOS
// ====================================

void lanzar_fase3(const DatosVuelos& datos) {
    if (datos.num_filas == 0) {
        std::cout << "Oye, primero tienes que cargar un CSV valido.\n";
        return;
    }

    int opcion_columna;
    int opcion_tipo;

    std::cout << "\n--- FASE 3: REDUCCION ---\n";
    std::cout << "Seleccione la columna:\n";
    std::cout << "1. DEP_DELAY\n";
    std::cout << "2. ARR_DELAY\n";
    std::cout << "3. WEATHER_DELAY\n";
    std::cout << "Opcion: ";
    std::cin >> opcion_columna;

    std::cout << "Seleccione el tipo de reduccion:\n";
    std::cout << "1. Maximo\n";
    std::cout << "2. Minimo\n";
    std::cout << "Opcion: ";
    std::cin >> opcion_tipo;

    const std::vector<float>* array_elegido = nullptr;
    const char* etiqueta_columna = "";

    switch (opcion_columna) {
    case 1:
        array_elegido = &datos.retraso_salida;
        etiqueta_columna = "DEP_DELAY";
        break;
    case 2:
        array_elegido = &datos.retraso_llegada;
        etiqueta_columna = "ARR_DELAY";
        break;
    case 3:
        array_elegido = &datos.retraso_meteorologia;
        etiqueta_columna = "WEATHER_DELAY";
        break;
    default:
        std::cout << "Columna no valida.\n";
        return;
    }

    bool es_maximo;
    if (opcion_tipo == 1) es_maximo = true;
    else if (opcion_tipo == 2) es_maximo = false;
    else {
        std::cout << "Opcion de reduccion no valida.\n";
        return;
    }

    int total_elementos = static_cast<int>(array_elegido->size());
    std::vector<int> datos_enteros(total_elementos);

    for (int i = 0; i < total_elementos; i++) {
        float valor = (*array_elegido)[i];

        if (std::isnan(valor)) {
            datos_enteros[i] = es_maximo ? INT_MIN : INT_MAX;
        }
        else {
            datos_enteros[i] = static_cast<int>(valor);
        }
    }

    int* d_datos_gpu = nullptr;
    cudaError_t error = cudaMalloc((void**)&d_datos_gpu, total_elementos * sizeof(int));
    if (error != cudaSuccess) {
        std::cout << "Fallo al reservar VRAM para los datos truncados: " << cudaGetErrorString(error) << "\n";
        return;
    }

    error = cudaMemcpy(d_datos_gpu, datos_enteros.data(), total_elementos * sizeof(int), cudaMemcpyHostToDevice);
    if (error != cudaSuccess) {
        std::cout << "Fallo al subir el array a la grafica: " << cudaGetErrorString(error) << "\n";
        cudaFree(d_datos_gpu);
        return;
    }

    int hilos_por_bloque = elegir_hilos_por_bloque();
    int num_bloques = calcular_num_bloques(total_elementos, hilos_por_bloque);
    std::size_t shared_mem_bytes = hilos_por_bloque * sizeof(int);

    std::cout << "\nLanzando las 4 pruebas sobre los mismos datos...\n";
    std::cout << "Columna objetivo: " << etiqueta_columna << "\n";
    std::cout << "Operacion: " << (es_maximo ? "Maximo" : "Minimo") << "\n";
    std::cout << "Configuracion de la grafica: " << num_bloques << " bloques, "
        << hilos_por_bloque << " hilos/bloque.\n\n";

    int final_1 = 0, final_2 = 0, final_3 = 0, final_4 = 0;

    bool paso_1 = test_variante_1_simple(d_datos_gpu, total_elementos, es_maximo, hilos_por_bloque, num_bloques, final_1);
    bool paso_2 = test_variante_2_basica(d_datos_gpu, total_elementos, es_maximo, hilos_por_bloque, num_bloques, shared_mem_bytes, final_2);
    bool paso_3 = test_variante_3_intermedia(d_datos_gpu, total_elementos, es_maximo, hilos_por_bloque, num_bloques, shared_mem_bytes, final_3);
    bool paso_4 = test_variante_4_arbol(d_datos_gpu, total_elementos, es_maximo, hilos_por_bloque, shared_mem_bytes, final_4);

    std::cout << "Resultados de las Variantes:\n";
    if (paso_1) std::cout << "3.1 Simple -> " << final_1 << "\n"; else std::cout << "3.1 Simple -> PETO\n";
    if (paso_2) std::cout << "3.2 Basica -> " << final_2 << "\n"; else std::cout << "3.2 Basica -> PETO\n";
    if (paso_3) std::cout << "3.3 Intermedia -> " << final_3 << "\n"; else std::cout << "3.3 Intermedia -> PETO\n";
    if (paso_4) std::cout << "3.4 Reduccion -> " << final_4 << "\n"; else std::cout << "3.4 Reduccion -> PETO\n";

    cudaFree(d_datos_gpu);

    RegistroCloud registro;
    registro.fase = "Fase 3";
    registro.fecha = obtener_fecha_actual();
    registro.parametros = std::string("columna=") + etiqueta_columna +
        ",operacion=" + (es_maximo ? "MAX" : "MIN");

    std::string r1 = paso_1 ? std::to_string(final_1) : "PETO";
    std::string r2 = paso_2 ? std::to_string(final_2) : "PETO";
    std::string r3 = paso_3 ? std::to_string(final_3) : "PETO";
    std::string r4 = paso_4 ? std::to_string(final_4) : "PETO";

    registro.resultado = "v1=" + r1 +
        ",v2=" + r2 +
        ",v3=" + r3 +
        ",v4=" + r4;

    if (preguntar_subida_cloud()) {
        registro.usuario = pedir_usuario_cloud();

        bool enviado_ok = enviar_registro_cloud(registro);

        if (enviado_ok) {
            std::cout << "\nResultado enviado correctamente al cloud.\n";
        }
        else {
            std::cout << "\nNo se pudo enviar al cloud. Se muestra el registro localmente:\n";
            mostrar_registro_cloud(registro);
        }
    }
}

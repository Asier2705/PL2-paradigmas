#include <iostream>
#include <vector>
#include <cstring>
#include <cmath>
#include <string>
#include <cuda_runtime.h>

#include "fase2_aterrizajes.h"
#include "info_gpu.h"
#include "cloud_envio.h"

#define TOPE_MATRICULA 16

// Estructura auxiliar para almacenar temporalmente en memoria Host (CPU)
// las coincidencias detectadas por la GPU antes de enviarlas al entorno Cloud.
struct CoincidenciaAterrizaje {
    std::string matricula;
    float arr_delay;
};

// Función interactiva: permite al usuario decidir cuántas coincidencias quiere
// subir al Cloud, evitando enviar demasiadas peticiones HTTP innecesarias.
int pedir_cantidad_subir_fase2(int total_disponibles) {
    int cantidad;
    std::cout << "Hay " << total_disponibles
        << " coincidencias. Cuantas quieres subir al cloud? ";
    std::cin >> cantidad;

    if (cantidad < 1) cantidad = 1;
    if (cantidad > total_disponibles) cantidad = total_disponibles;

    return cantidad;
}


// =========================================================================
// MEMORIA CONSTANTE CUDA
// =========================================================================


//Usamos memoria constante porque el umbral no cambia y as� todos los hilos del warp lo leen a la vez de la cach� de manera r�pida
__constant__ int umbral_llegada;


// =========================================================================
// FUNCIÓN AUXILIAR DEVICE: Copia de matrícula
// =========================================================================
//Funci�n auxiliar en la GPU para copiar las matr�culas letra a letra
__device__ void clonar_matricula(char* destino, const char* origen) {
    for (int i = 0; i < TOPE_MATRICULA; i++) {
        destino[i] = origen[i];
        if (origen[i] == '\0') {
            break; //Cortamos si llegamos al final del string
        }
    }
}


// =========================================================================
// KERNEL CUDA: Evaluación paralela del umbral de aterrizaje
// =========================================================================
//Kernel principal de la Fase 2
__global__ void buscar_aterrizajes_gpu(
    const float* array_llegadas,
    const char* array_matriculas,
    int total_vuelos,
    int* contador_excesos,
    char* matriculas_pilladas,
    float* tiempos_pillados
) {
    //Calculamos qu� vuelo le toca a este hilo
    int id_hilo = blockIdx.x * blockDim.x + threadIdx.x;

    if (id_hilo >= total_vuelos) {
        return;
    }

    float minutos = array_llegadas[id_hilo];

    //Saltamos los huecos vac�os del CSV
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
        //Usamos atomicAdd para poner en fila a los hilos ya que si no podr�an pisarse al intentar sumar al contador a la vez
        //"pos" ser� el �ndice �nico donde este hilo guardar� su avi�n
        int pos = atomicAdd(contador_excesos, 1);

        //Calculamos los punteros bas�ndonos en nuestra posici�n �nica
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
        std::cout << "Primero hay que cargar un CSV v�lido.\n";
        return;
    }

    int limite;
    std::cout << "\n--- FASE 2: RETRASO EN ATERRIZAJES ---\n";
    std::cout << "Introduce el umbral (minutos): ";
    std::cin >> limite;

    int total = static_cast<int>(datos.retraso_llegada.size());

    //Aplanamos las matr�culas (strings de C++) en un array gigante de chars para que la GPU no colapse
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

    // Reservamos salida con tama�o total por si acaso todos los vuelos cumplen la condici�n
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

    //Ponemos el contador a 0 en la gr�fica
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

    //Calculamos el hardware din�micamente
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

    //Nos traemos cu�ntos aviones han entrado finalmente en el umbral
    int total_detectados = 0;
    cudaMemcpy(&total_detectados, d_contador, sizeof(int), cudaMemcpyDeviceToHost);

    std::cout << "Total de aviones detectados: " << total_detectados << "\n";

    //Guardamos en CPU las coincidencias detectadas para luego subir las que el usuario quiera
    std::vector<CoincidenciaAterrizaje> coincidencias_detectadas;
    coincidencias_detectadas.reserve(total_detectados);

    //Si ha cogido a alguno, nos bajamos los resultados para ense�arlos
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

        //Construimos el vector de coincidencias completo
        for (int i = 0; i < total_detectados; i++) {
            CoincidenciaAterrizaje c;
            c.matricula = std::string(&matriculas_salida_host[i * TOPE_MATRICULA]);
            c.arr_delay = tiempos_salida_host[i];
            coincidencias_detectadas.push_back(c);
        }

        //Imprimimos un m�ximo de 10 para no colapsar la consola
        int mostrar = (total_detectados < 10) ? total_detectados : 10;

        for (int i = 0; i < mostrar; i++) {
            std::cout << "  [" << i << "] "
                << coincidencias_detectadas[i].matricula
                << " -> " << coincidencias_detectadas[i].arr_delay << " min\n";
        }
    }

    //Liberamos la VRAM antes de pasar a la parte cloud
    cudaFree(d_llegadas);
    cudaFree(d_matriculas);
    cudaFree(d_contador);
    cudaFree(d_matriculas_salida);
    cudaFree(d_tiempos_salida);

    if (total_detectados == 0) {
        std::cout << "No hay coincidencias para subir al cloud.\n";
        return;
    }


    // =========================================================================
    // MÓDULO CLOUD: Interacción y envío de peticiones
    // =========================================================================


    if (preguntar_subida_cloud()) {
        std::string usuario = pedir_usuario_cloud();
        int cantidad_subir = pedir_cantidad_subir_fase2(total_detectados);

        int enviados_ok = 0;

        for (int i = 0; i < cantidad_subir; i++) {
            RegistroCloud registro;
            registro.usuario = usuario;
            registro.fase = "Fase 2";
            registro.fecha = obtener_fecha_actual();
            registro.parametros = "umbral=" + std::to_string(limite);
            
            // Empaquetado de los metadatos relevantes de cada coincidencia
            // detectada durante la ejecución de la Fase 2.
            registro.resultado =
                "coincidencia=" + std::to_string(i + 1) + "/" + std::to_string(total_detectados) +
                ",TAIL_NUM=" + coincidencias_detectadas[i].matricula +
                ",ARR_DELAY=" + std::to_string(coincidencias_detectadas[i].arr_delay);

            bool enviado_ok = enviar_registro_cloud(registro);

            if (enviado_ok) {
                enviados_ok++;
            }
            else {
                // Si falla el envío al Cloud, no se aborta el programa.
                // Se muestra el registro localmente como mecanismo de contingencia.
                std::cout << "\nNo se pudo enviar esta coincidencia al cloud. Se muestra el registro localmente:\n";
                mostrar_registro_cloud(registro);
            }
        }

        std::cout << "\nResumen de subida: " << enviados_ok
            << " de " << cantidad_subir << " coincidencias enviadas correctamente.\n";
    }
}

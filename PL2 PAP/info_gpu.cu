#include <iostream>
#include <cuda_runtime.h>
#include "info_gpu.h"

//Muestra por pantalla las caracteristicas de la tarjeta grafica
void mostrar_info_gpu() {
    int num_dispositivos = 0;
    cudaError_t estado = cudaGetDeviceCount(&num_dispositivos);

    if (estado != cudaSuccess || num_dispositivos == 0) {
        std::cout << "No se ha detectado una GPU CUDA disponible.\n\n";
        return;
    }

    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);

    std::cout << "GPU detectada: " << prop.name << "\n";
    std::cout << "Max hilos por bloque: " << prop.maxThreadsPerBlock << "\n";
    std::cout << "Multiprocesadores: " << prop.multiProcessorCount << "\n\n";
}

//Obtiene dinamicamente el limite de hilos de la arquitectura actual
int elegir_hilos_por_bloque() {
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    return prop.maxThreadsPerBlock;
}

//Calcula la cantidad de bloques necesarios asegurando que no queden datos fuera
int calcular_num_bloques(std::size_t n, int hilos_por_bloque) {
    return static_cast<int>((n + hilos_por_bloque - 1) / hilos_por_bloque);
}
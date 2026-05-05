#pragma once

#include <cstddef>

//Muestra las especificaciones del hardware disponible
void mostrar_info_gpu();

//Obtiene el limite real de hilos soportados por bloque
int elegir_hilos_por_bloque();

//Calcula la topologia del grid evitando desbordamientos
int calcular_num_bloques(std::size_t n, int hilos_por_bloque);
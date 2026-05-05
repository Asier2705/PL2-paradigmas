#pragma once

#include <vector>
#include <string>
#include <cstddef>

//Estructura principal para almacenar las columnas del dataset en la memoria del Host
struct DatosVuelos {
    std::size_t num_filas = 0;

    std::vector<float> retraso_salida;
    std::vector<float> retraso_llegada;
    std::vector<float> retraso_meteorologia;

    std::vector<int> id_aeropuerto_origen;
    std::vector<int> id_aeropuerto_destino;

    std::vector<std::string> matricula_avion;
    std::vector<std::string> aeropuerto_origen;
    std::vector<std::string> aeropuerto_destino;
};
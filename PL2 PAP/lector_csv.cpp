#include "lector_csv.h"

#include <fstream>
#include <iostream>
#include <vector>
#include <string>
#include <unordered_map>
#include <limits>
#include <cmath>

//Divide una linea CSV respetando comillas para evitar rupturas de formato
static std::vector<std::string> dividir_csv(const std::string& linea) {
    std::vector<std::string> campos;
    std::string actual;
    bool dentro_comillas = false;

    for (char c : linea) {
        if (c == '"') {
            dentro_comillas = !dentro_comillas;
        }
        else if (c == ',' && !dentro_comillas) {
            campos.push_back(actual);
            actual.clear();
        }
        else {
            actual += c;
        }
    }

    campos.push_back(actual);
    return campos;
}

//Convierte la cadena de texto a float gestionando las celdas vacias con NAN
static float convertir_a_float_o_nan(const std::string& texto) {
    if (texto.empty()) {
        return std::numeric_limits<float>::quiet_NaN();
    }

    try {
        return std::stof(texto);
    }
    catch (...) {
        return std::numeric_limits<float>::quiet_NaN();
    }
}

//Convierte la cadena a int devolviendo negativo en caso de celda vacia
static int convertir_a_int_o_menos_uno(const std::string& texto) {
    if (texto.empty()) {
        return -1;
    }

    try {
        return std::stoi(texto);
    }
    catch (...) {
        return -1;
    }
}

//Abre el archivo y estructura cada columna en su propio vector unidimensional
bool cargar_csv(const std::string& ruta, DatosVuelos& datos) {
    std::ifstream archivo(ruta);

    if (!archivo.is_open()) {
        return false;
    }

    //Limpiamos las estructuras por si el usuario decide recargar los datos
    datos.num_filas = 0;
    datos.retraso_salida.clear();
    datos.retraso_llegada.clear();
    datos.retraso_meteorologia.clear();
    datos.id_aeropuerto_origen.clear();
    datos.id_aeropuerto_destino.clear();
    datos.matricula_avion.clear();
    datos.aeropuerto_origen.clear();
    datos.aeropuerto_destino.clear();

    std::string linea;

    //Lectura de la cabecera
    if (!std::getline(archivo, linea)) {
        return false;
    }

    std::vector<std::string> cabecera = dividir_csv(linea);
    std::unordered_map<std::string, int> indice_columna;

    for (int i = 0; i < static_cast<int>(cabecera.size()); i++) {
        indice_columna[cabecera[i]] = i;
    }

    //Validacion de las columnas requeridas por el enunciado
    const std::vector<std::string> obligatorias = {
        "DEP_DELAY",
        "ARR_DELAY",
        "WEATHER_DELAY",
        "TAIL_NUM",
        "ORIGIN_AIRPORT",
        "DEST_AIRPORT",
        "ORIGIN_SEQ_ID",
        "DEST_SEQ_ID"
    };

    for (const auto& nombre : obligatorias) {
        if (indice_columna.find(nombre) == indice_columna.end()) {
            std::cout << "Falta la columna obligatoria: " << nombre << "\n";
            return false;
        }
    }

    int idx_dep_delay = indice_columna["DEP_DELAY"];
    int idx_arr_delay = indice_columna["ARR_DELAY"];
    int idx_weather_delay = indice_columna["WEATHER_DELAY"];
    int idx_tail_num = indice_columna["TAIL_NUM"];
    int idx_origin_airport = indice_columna["ORIGIN_AIRPORT"];
    int idx_dest_airport = indice_columna["DEST_AIRPORT"];
    int idx_origin_seq_id = indice_columna["ORIGIN_SEQ_ID"];
    int idx_dest_seq_id = indice_columna["DEST_SEQ_ID"];

    //Lectura secuencial de las filas de datos
    while (std::getline(archivo, linea)) {
        if (linea.empty()) {
            continue;
        }

        std::vector<std::string> campos = dividir_csv(linea);

        //Evitamos fallos de segmentacion si la fila esta incompleta
        int max_idx = idx_dep_delay;
        if (idx_arr_delay > max_idx) max_idx = idx_arr_delay;
        if (idx_weather_delay > max_idx) max_idx = idx_weather_delay;
        if (idx_tail_num > max_idx) max_idx = idx_tail_num;
        if (idx_origin_airport > max_idx) max_idx = idx_origin_airport;
        if (idx_dest_airport > max_idx) max_idx = idx_dest_airport;
        if (idx_origin_seq_id > max_idx) max_idx = idx_origin_seq_id;
        if (idx_dest_seq_id > max_idx) max_idx = idx_dest_seq_id;

        if (static_cast<int>(campos.size()) <= max_idx) {
            continue;
        }

        datos.retraso_salida.push_back(convertir_a_float_o_nan(campos[idx_dep_delay]));
        datos.retraso_llegada.push_back(convertir_a_float_o_nan(campos[idx_arr_delay]));
        datos.retraso_meteorologia.push_back(convertir_a_float_o_nan(campos[idx_weather_delay]));

        datos.id_aeropuerto_origen.push_back(convertir_a_int_o_menos_uno(campos[idx_origin_seq_id]));
        datos.id_aeropuerto_destino.push_back(convertir_a_int_o_menos_uno(campos[idx_dest_seq_id]));

        datos.matricula_avion.push_back(campos[idx_tail_num]);
        datos.aeropuerto_origen.push_back(campos[idx_origin_airport]);
        datos.aeropuerto_destino.push_back(campos[idx_dest_airport]);
    }

    datos.num_filas = datos.retraso_salida.size();

    return true;
}
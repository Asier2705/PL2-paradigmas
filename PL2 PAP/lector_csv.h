#pragma once

#include <string>
#include "datos_vuelos.h"

//Parsea el archivo delimitado por comas y estructura los datos lineales
bool cargar_csv(const std::string& ruta, DatosVuelos& datos);
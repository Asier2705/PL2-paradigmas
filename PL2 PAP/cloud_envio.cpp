#include "cloud_envio.h"
#include <iostream>
#include <chrono>
#include <ctime>
#include <iomanip>
#include <sstream>

std::string obtener_fecha_actual() {
    auto ahora = std::chrono::system_clock::now();
    std::time_t t = std::chrono::system_clock::to_time_t(ahora);
    std::tm tm_local{};

#ifdef _WIN32
    localtime_s(&tm_local, &t);
#else
    tm_local = *std::localtime(&t);
#endif

    std::ostringstream oss;
    oss << std::put_time(&tm_local, "%Y-%m-%d %H:%M:%S");
    return oss.str();
}

std::string pedir_usuario_cloud() {
    std::string usuario;
    std::cout << "Introduce el nombre de usuario: ";
    std::cin >> usuario;
    return usuario;
}

bool preguntar_subida_cloud() {
    char respuesta;
    std::cout << "¿Quieres enviar este resultado al Cloud? (s/n): ";
    std::cin >> respuesta;
    return respuesta == 's' || respuesta == 'S';
}

void mostrar_registro_cloud(const RegistroCloud& registro) {
    std::cout << "\n--- REGISTRO PREPARADO PARA CLOUD ---\n";
    std::cout << "Usuario: " << registro.usuario << "\n";
    std::cout << "Fecha: " << registro.fecha << "\n";
    std::cout << "Fase: " << registro.fase << "\n";
    std::cout << "Parametros: " << registro.parametros << "\n";
    std::cout << "Resultado: " << registro.resultado << "\n";
}
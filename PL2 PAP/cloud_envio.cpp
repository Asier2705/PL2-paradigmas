#include "cloud_envio.h"
#include <iostream>
#include <chrono>
#include <ctime>
#include <iomanip>
#include <sstream>
#include <fstream> // añadido para poder crear archivos

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

void enviar_registro_cloud(const RegistroCloud& registro) {
    // 1. Creamos un archivo temporal con formato JSON
    std::ofstream archivo_json("payload.json");
    archivo_json << "{\n";
    archivo_json << "  \"usuario\": \"" << registro.usuario << "\",\n";
    archivo_json << "  \"fecha\": \"" << registro.fecha << "\",\n";
    archivo_json << "  \"fase\": \"" << registro.fase << "\",\n";
    archivo_json << "  \"parametros\": \"" << registro.parametros << "\",\n";
    archivo_json << "  \"resultado\": \"" << registro.resultado << "\"\n";
    archivo_json << "}";
    archivo_json.close();

    std::cout << "\n[Conectando con el servidor en localhost:3000...]\n";

    // 2. Usamos el comando curl de Windows para enviar el archivo al Visual Azul
    // Cambiaremos localhost por la URL de Azure cuando llegue el momento
    int resultado_red = system("curl -s -X POST http://localhost:3000/api/resultados -H \"Content-Type: application/json\" -d @payload.json");

    if (resultado_red == 0) {
        std::cout << "\n¡Exito! Los datos han volado a tu base de datos.\n";
    }
    else {
        std::cout << "\n[ERROR] El servidor Azul no responde. Comprueba que 'node index.js' esta encendido.\n";
    }
}
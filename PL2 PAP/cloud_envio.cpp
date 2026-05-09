#include "cloud_envio.h"

#include <iostream>
#include <sstream>
#include <iomanip>
#include <ctime>
#include <windows.h>
#include <winhttp.h>

#pragma comment(lib, "winhttp.lib")

namespace {
    const wchar_t* HOST_CLOUD = L"pl2paradigmasapi-bpfqagahgjdydvc7.scm.spaincentral-01.azurewebsites.net";
    const wchar_t* RUTA_API = L"/api/resultados";
    const INTERNET_PORT PUERTO_CLOUD = INTERNET_DEFAULT_HTTPS_PORT;

    std::string escapar_json(const std::string& texto) {
        std::ostringstream out;
        for (char c : texto) {
            switch (c) {
            case '\"': out << "\\\""; break;
            case '\\': out << "\\\\"; break;
            case '\b': out << "\\b"; break;
            case '\f': out << "\\f"; break;
            case '\n': out << "\\n"; break;
            case '\r': out << "\\r"; break;
            case '\t': out << "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    out << "\\u"
                        << std::hex << std::setw(4) << std::setfill('0')
                        << static_cast<int>(static_cast<unsigned char>(c));
                }
                else {
                    out << c;
                }
            }
        }
        return out.str();
    }

    std::string construir_json(const RegistroCloud& registro) {
        std::ostringstream json;
        json << "{"
            << "\"usuario\":\"" << escapar_json(registro.usuario) << "\","
            << "\"fecha\":\"" << escapar_json(registro.fecha) << "\","
            << "\"fase\":\"" << escapar_json(registro.fase) << "\","
            << "\"parametros\":\"" << escapar_json(registro.parametros) << "\","
            << "\"resultado\":\"" << escapar_json(registro.resultado) << "\""
            << "}";
        return json.str();
    }

    void cerrar_handle(HINTERNET h) {
        if (h != nullptr) {
            WinHttpCloseHandle(h);
        }
    }
}

std::string obtener_fecha_actual() {
    std::time_t ahora = std::time(nullptr);
    std::tm tiempo_local{};
    localtime_s(&tiempo_local, &ahora);

    std::ostringstream out;
    out << std::put_time(&tiempo_local, "%Y-%m-%d %H:%M:%S");
    return out.str();
}

bool preguntar_subida_cloud() {
    char respuesta;
    std::cout << "\nQuieres enviar este resultado al cloud? (s/n): ";
    std::cin >> respuesta;
    return respuesta == 's' || respuesta == 'S';
}

std::string pedir_usuario_cloud() {
    std::string usuario;
    std::cout << "Introduce el nombre de usuario: ";
    std::cin >> usuario;
    return usuario;
}

void mostrar_registro_cloud(const RegistroCloud& registro) {
    std::cout << "\n--- REGISTRO PREPARADO PARA CLOUD ---\n";
    std::cout << "Usuario: " << registro.usuario << "\n";
    std::cout << "Fecha: " << registro.fecha << "\n";
    std::cout << "Fase: " << registro.fase << "\n";
    std::cout << "Parametros: " << registro.parametros << "\n";
    std::cout << "Resultado: " << registro.resultado << "\n";
}

bool enviar_registro_cloud(const RegistroCloud& registro) {
    std::string cuerpo_json = construir_json(registro);

    HINTERNET hSesion = WinHttpOpen(
        L"PL2-CUDA-Client/1.0",
        WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS,
        0
    );

    if (!hSesion) {
        std::cout << "Error al abrir sesion WinHTTP.\n";
        return false;
    }

    WinHttpSetTimeouts(hSesion, 5000, 5000, 10000, 10000);

    HINTERNET hConexion = WinHttpConnect(hSesion, HOST_CLOUD, PUERTO_CLOUD, 0);
    if (!hConexion) {
        std::cout << "Error al conectar con el host cloud.\n";
        cerrar_handle(hSesion);
        return false;
    }

    HINTERNET hRequest = WinHttpOpenRequest(
        hConexion,
        L"POST",
        RUTA_API,
        nullptr,
        WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        WINHTTP_FLAG_SECURE
    );

    if (!hRequest) {
        std::cout << "Error al crear la peticion HTTP.\n";
        cerrar_handle(hConexion);
        cerrar_handle(hSesion);
        return false;
    }

    const wchar_t* cabeceras = L"Content-Type: application/json\r\n";

    BOOL enviado = WinHttpSendRequest(
        hRequest,
        cabeceras,
        static_cast<DWORD>(-1L),
        (LPVOID)cuerpo_json.data(),
        static_cast<DWORD>(cuerpo_json.size()),
        static_cast<DWORD>(cuerpo_json.size()),
        0
    );

    if (!enviado) {
        std::cout << "Error al enviar la peticion al cloud.\n";
        cerrar_handle(hRequest);
        cerrar_handle(hConexion);
        cerrar_handle(hSesion);
        return false;
    }

    BOOL recibida = WinHttpReceiveResponse(hRequest, nullptr);
    if (!recibida) {
        std::cout << "Error al recibir respuesta del cloud.\n";
        cerrar_handle(hRequest);
        cerrar_handle(hConexion);
        cerrar_handle(hSesion);
        return false;
    }

    DWORD statusCode = 0;
    DWORD tam = sizeof(statusCode);

    BOOL okStatus = WinHttpQueryHeaders(
        hRequest,
        WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
        WINHTTP_HEADER_NAME_BY_INDEX,
        &statusCode,
        &tam,
        WINHTTP_NO_HEADER_INDEX
    );

    cerrar_handle(hRequest);
    cerrar_handle(hConexion);
    cerrar_handle(hSesion);

    if (!okStatus) {
        std::cout << "No se pudo leer el codigo HTTP de respuesta.\n";
        return false;
    }

    if (statusCode >= 200 && statusCode < 300) {
        return true;
    }

    std::cout << "El servidor respondio con HTTP " << statusCode << ".\n";
    return false;
}
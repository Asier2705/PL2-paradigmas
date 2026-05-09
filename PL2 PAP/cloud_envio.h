#pragma once
#include <string>

struct RegistroCloud {
    std::string usuario;
    std::string fecha;
    std::string fase;
    std::string parametros;
    std::string resultado;
};

std::string obtener_fecha_actual();
bool preguntar_subida_cloud();
std::string pedir_usuario_cloud();
void mostrar_registro_cloud(const RegistroCloud& registro);

// NUEVO
bool enviar_registro_cloud(const RegistroCloud& registro);
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
std::string pedir_usuario_cloud();
bool preguntar_subida_cloud();
void mostrar_registro_cloud(const RegistroCloud& registro);

// añadido
// Función para enviar los datos por internet
void enviar_registro_cloud(const RegistroCloud& registro);
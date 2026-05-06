#include <iostream>
#include <string>
#include <ctime> // Necesario para obtener la fecha y la hora

#include "datos_vuelos.h"
#include "lector_csv.h"
#include "menu.h"
#include "info_gpu.h"
#include "fase1_despegues.h"
#include "fase2_aterrizajes.h"
#include "fase3_reduccion.h"
#include "fase4_histograma.h"

int main() {
    DatosVuelos datos;
    int opcion = -1;
    std::string ruta_csv = "Airline_dataset.csv";

    std::cout << "=========================================\n";
    std::cout << "   PL1 - Manipulacion de Datos con CUDA\n";
    std::cout << "=========================================\n\n";

    //Carga inicial del dataset en la memoria del procesador
    if (!cargar_csv(ruta_csv, datos)) {
        std::cout << "No se ha podido cargar el CSV.\n";
        return 1;
    }

    std::cout << "CSV cargado correctamente.\n";
    std::cout << "Numero de filas leidas: " << datos.num_filas << "\n\n";

    //Impresion de control para verificar que el parseo de la cabecera es correcto
    if (datos.num_filas > 0) {
        std::cout << "Primera fila cargada:\n";
        std::cout << "DEP_DELAY: " << datos.retraso_salida[0] << "\n";
        std::cout << "ARR_DELAY: " << datos.retraso_llegada[0] << "\n";
        std::cout << "WEATHER_DELAY: " << datos.retraso_meteorologia[0] << "\n";
        std::cout << "TAIL_NUM: " << datos.matricula_avion[0] << "\n";
        std::cout << "ORIGIN_AIRPORT: " << datos.aeropuerto_origen[0] << "\n";
        std::cout << "DEST_AIRPORT: " << datos.aeropuerto_destino[0] << "\n";
        std::cout << "ORIGIN_SEQ_ID: " << datos.id_aeropuerto_origen[0] << "\n";
        std::cout << "DEST_SEQ_ID: " << datos.id_aeropuerto_destino[0] << "\n\n";
    }

    //Mostramos las especificaciones de la grafica
    mostrar_info_gpu();

    //Bucle principal de interaccion con el usuario
    do {
        opcion = mostrar_menu_principal();

        switch (opcion) {
        case 1:
            lanzar_fase1(datos);
            break;
        case 2:
            lanzar_fase2(datos);
            break;
        case 3:
            lanzar_fase3(datos);
            break;
        case 4:
            lanzar_fase4(datos);
            break;
        case 5: { // Usamos llaves para limitar el alcance de las variables locales
            int fase_cloud;
            std::cout << "\n¿Que fase deseas ejecutar y subir al Cloud? (1-4): ";
            std::cin >> fase_cloud; // Cumplimos el requisito de solicitar la fase a ejecutar[cite: 1]

            // Ejecutamos la fase correspondiente elegida por el usuario
            if (fase_cloud == 1) lanzar_fase1(datos);
            else if (fase_cloud == 2) lanzar_fase2(datos);
            else if (fase_cloud == 3) lanzar_fase3(datos);
            else if (fase_cloud == 4) lanzar_fase4(datos);
            else {
                std::cout << "Fase no valida. Cancelando la conexion al Cloud.\n";
                break;
            }

            // Recopilamos el nombre de usuario
            std::string usuario_cloud;
            std::cout << "\nIntroduce un nombre de usuario para el registro (alfanumerico): ";
            std::cin >> usuario_cloud;

            // Recopilamos la fecha y la hora actual
            std::time_t t = std::time(nullptr);
            char buffer[100];
            std::strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", std::localtime(&t));
            std::string fecha_hora(buffer);

            // Print de comprobación temporal para ver que recopilamos los datos correctamente
            std::cout << "\n[DEBUG] Datos listos para el paquete Cloud:\n";
            std::cout << "-> Usuario: " << usuario_cloud << "\n";
            std::cout << "-> Fecha: " << fecha_hora << "\n";
            std::cout << "-> Fase ejecutada: Fase " << fase_cloud << "\n";

            // Empaquetar resultados en JSON y hacer la petición HTTP
            // Construimos el JSON manualmente escapando las comillas con \"
            std::string json_payload = "{";
            json_payload += "\"usuario\": \"" + usuario_cloud + "\", ";
            json_payload += "\"fecha\": \"" + fecha_hora + "\", ";
            json_payload += "\"fase\": " + std::to_string(fase_cloud) + ", ";
            json_payload += "\"resultados\": \"Datos de prueba generados por la fase\""; // TODO: Conectar con resultado real
            json_payload += "}";

            std::cout << "\n[DEBUG] JSON generado: \n" << json_payload << "\n";

            break;
        }
        case 0:
            std::cout << "Saliendo del programa...\n";
            break;
        default:
            std::cout << "Opcion no valida.\n";
            break;
        }

        std::cout << "\n";
    } while (opcion != 0);

    return 0;
}
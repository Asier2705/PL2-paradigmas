#include <iostream>
#include "menu.h"

//Despliegue del menu interactivo por consola
int mostrar_menu_principal() {
    int opcion;

    std::cout << "------ MENU PRINCIPAL ------\n";
    std::cout << "1. Fase 1 - Retraso en despegues\n";
    std::cout << "2. Fase 2 - Retraso en aterrizajes\n";
    std::cout << "3. Fase 3 - Reduccion\n";
    std::cout << "4. Fase 4 - Histograma\n";
    std::cout << "5. Subir los datos al Cloud\n"; // opción añadida
    std::cout << "0. Salir\n";
    std::cout << "Seleccione una opcion: ";
    std::cin >> opcion;

    return opcion;
}
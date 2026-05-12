##SCRIPT DE CREACIÓN DE BASE DE DATOS (AZURE SQL)
##Descripción: Instancia la tabla centralizada para el histórico de vuelos.

CREATE TABLE Resultados (
    id INT IDENTITY(1,1) PRIMARY KEY, #clave primaria autoincremental para poder aplicar despues el 'ORDER BY DESC' en la API
    usuario NVARCHAR(100), #quien realizó la pedición desde C++
    fecha NVARCHAR(100), #momento exacto
    fase NVARCHAR(100), #identificador de la fase
    parametros NVARCHAR(MAX), #configuraciones seleccionadas por el usuario
    resultado NVARCHAR(MAX) #salida generada por CUDA
);
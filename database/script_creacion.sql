CREATE TABLE Resultados (
    id INT IDENTITY(1,1) PRIMARY KEY,
    usuario NVARCHAR(100),
    fecha NVARCHAR(100),
    fase NVARCHAR(100),
    parametros NVARCHAR(MAX),
    resultado NVARCHAR(MAX)
);
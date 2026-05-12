require('dotenv').config();
const express = require('express');
const path = require('node:path');
const sql = require('mssql');

const app = express();

// Prepara el servidor para entender los datos que llegan en formato JSON
app.use(express.json());
// Servir archivos estáticos (HTML, CSS, JS del panel de control)
app.use(express.static(__dirname));

const port = process.env.PORT || 3000;

// Por seguridad, la conexión a Azure SQL se realiza estrictamente mediante 
// variables de entorno. Las credenciales NUNCA se exponen en el código fuente.
const dbConfig = {
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    server: process.env.DB_SERVER,
    database: process.env.DB_NAME,
    options: {
        encrypt: true,
        trustServerCertificate: false
    }
};

// -------------------------------------------------------------------------
// ENDPOINT: RAÍZ (Frontend)
// -------------------------------------------------------------------------
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

// -------------------------------------------------------------------------
// ENDPOINT: LECTURA DE DATOS (GET)
// Propósito: Recuperar el historial completo de ejecuciones para el panel web.
// -------------------------------------------------------------------------
app.get('/api/resultados', async (req, res) => {
    try {
        await sql.connect(dbConfig);

        // Cumplimiento del enunciado: Se ordenan los registros de forma 
        // descendente para mostrar las ejecuciones más recientes primero.
        const result = await sql.query(`
            SELECT usuario, fecha, fase, parametros, resultado
            FROM Resultados
            ORDER BY fecha DESC
        `);

        res.json(result.recordset);
    } catch (error) {
        console.error('Error en GET /api/resultados:', error);
        res.status(500).json({ error: 'Error al leer los resultados' });
    }
});

// -------------------------------------------------------------------------
// ENDPOINT: INSERCIÓN DE DATOS (POST)
// Propósito: Recibir el JSON desde WinHTTP (C++) y persistirlo en la nube.
// -------------------------------------------------------------------------
app.post('/api/resultados', async (req, res) => {
    const { usuario, fecha, fase, parametros, resultado } = req.body;

    // 1. Validación inicial de integridad del paquete de datos
    if (!usuario || !fecha || !fase || !parametros || !resultado) {
        return res.status(400).json({
            error: 'Faltan campos obligatorios'
        });
    }

    try {
        await sql.connect(dbConfig);

        // 2. Prevención de Inyección SQL 
        // Se parametrizan los inputs mapeando los tipos de datos exactos de Azure.
        // Esto garantiza que el texto del usuario se trate como dato y no como código ejecutable.
        const request = new sql.Request();
        request.input('usuario', sql.VarChar(100), usuario);
        request.input('fecha', sql.DateTime, new Date(fecha));
        request.input('fase', sql.VarChar(50), fase);
        request.input('parametros', sql.VarChar(sql.MAX), parametros);
        request.input('resultado', sql.VarChar(sql.MAX), resultado);

        // 3. Ejecución segura de la inserción
        await request.query(`
            INSERT INTO Resultados (usuario, fecha, fase, parametros, resultado)
            VALUES (@usuario, @fecha, @fase, @parametros, @resultado)
        `);

        // Respuesta HTTP 201 (Created) que lee nuestro cliente C++
        res.status(201).json({
            mensaje: 'Resultado guardado correctamente'
        });
    } catch (error) {
        console.error('Error en POST /api/resultados:', error);
        res.status(500).json({ error: 'Error al guardar el resultado' });
    }
});

// -------------------------------------------------------------------------
// INICIO DEL SERVIDOR
// -------------------------------------------------------------------------
app.listen(port, () => {
    console.log(`Servidor activo en puerto ${port}`);
});
require('dotenv').config();
const express = require('express');
const path = require('node:path');
const sql = require('mssql');

const app = express();
app.use(express.json());
app.use(express.static(__dirname));

const port = process.env.PORT || 3000;

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

app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

app.get('/api/resultados', async (req, res) => {
    try {
        await sql.connect(dbConfig);

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

app.post('/api/resultados', async (req, res) => {
    const { usuario, fecha, fase, parametros, resultado } = req.body;

    if (!usuario || !fecha || !fase || !parametros || !resultado) {
        return res.status(400).json({
            error: 'Faltan campos obligatorios'
        });
    }

    try {
        await sql.connect(dbConfig);

        const request = new sql.Request();
        request.input('usuario', sql.VarChar(100), usuario);
        request.input('fecha', sql.DateTime, new Date(fecha));
        request.input('fase', sql.VarChar(50), fase);
        request.input('parametros', sql.VarChar(sql.MAX), parametros);
        request.input('resultado', sql.VarChar(sql.MAX), resultado);

        await request.query(`
            INSERT INTO Resultados (usuario, fecha, fase, parametros, resultado)
            VALUES (@usuario, @fecha, @fase, @parametros, @resultado)
        `);

        res.status(201).json({
            mensaje: 'Resultado guardado correctamente'
        });
    } catch (error) {
        console.error('Error en POST /api/resultados:', error);
        res.status(500).json({ error: 'Error al guardar el resultado' });
    }
});

app.listen(port, () => {
    console.log(`Servidor activo en puerto ${port}`);
});
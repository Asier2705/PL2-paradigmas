require('dotenv').config();
const express = require('express');
const path = require('node:path');

const app = express();
app.use(express.json());

let resultados = [];

const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

app.get('/api/resultados', (req, res) => {
    res.json(resultados);
});

app.post('/api/resultados', (req, res) => {
    const { usuario, fecha, fase, parametros, resultado } = req.body;

    if (!usuario || !fecha || !fase || !parametros || !resultado) {
        return res.status(400).json({
            error: 'Faltan campos obligatorios'
        });
    }

    resultados.push({ usuario, fecha, fase, parametros, resultado });

    resultados.sort((a, b) => new Date(b.fecha) - new Date(a.fecha));

    res.status(201).json({
        mensaje: 'Resultado guardado correctamente'
    });
});

app.listen(port, () => {
    console.log(`Servidor activo en puerto ${port}`);
});
@echo off
chcp 65001 > nul
title RealTracks - Microserviço Local de Importação (YouTube & Spotify)
cls
echo ================================================================
echo   RealTracks - Servidor Local de Importação de Músicas
echo ================================================================
echo.
echo  * Vantagem: Roda na sua internet de casa (IP residencial).
echo  * Zero bloqueios de bot do YouTube e zero necessidade de cookies!
echo.
cd /d "%~dp0\cloud_importer"
if not exist node_modules (
    echo [1/2] Instalando dependencias do Node.js...
    call npm.cmd install
)
echo [2/2] Iniciando servidor em http://localhost:3000...
echo.
echo ================================================================
echo  Pronto! No RealTracks, a URL do Cloud Importer deve ser:
echo  http://localhost:3000
echo.
echo  (Mantenha esta janela aberta enquanto cadastra musicas por link)
echo ================================================================
echo.
node server.js
pause

@echo off
:: Abrir-Ollama-Local.cmd — Abre a interface portátil do Ollama local.
:: Clique duplo ou execute no Explorer / Prompt de Comando.
:: Não requer administrador. Não altera configurações do sistema.

chcp 65001 >nul 2>&1

powershell -ExecutionPolicy Bypass -File "%~dp0Ollama-Local.ps1"

:: Se o PowerShell não estiver disponível, exibe mensagem.
if errorlevel 1 (
    echo.
    echo [ERRO] Nao foi possivel abrir Ollama-Local.ps1 via PowerShell.
    echo        Verifique se o PowerShell esta instalado e tente novamente.
    echo.
    pause
)

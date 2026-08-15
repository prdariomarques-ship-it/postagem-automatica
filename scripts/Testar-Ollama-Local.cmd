@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1

:: ─────────────────────────────────────────────────────────────
:: Testar-Ollama-Local.cmd — Diagnóstico rápido do Ollama local
:: Uso: clique duplo ou execute no Prompt de Comando / Terminal.
:: Não faz chamadas externas. Não lê nem exibe arquivos .env.
:: ─────────────────────────────────────────────────────────────

set "MODELO=%OLLAMA_MODEL%"
if "%MODELO%"=="" set "MODELO=qwen3:4b"

echo.
echo ════════════════════════════════════════════════════════════
echo   Testar-Ollama-Local — diagnóstico do ambiente local
echo ════════════════════════════════════════════════════════════
echo.

:: 1. Verificar instalação
where ollama >nul 2>&1
if errorlevel 1 (
    echo [FALHA] Ollama nao encontrado no PATH.
    echo         Baixe em: https://ollama.com/download
    echo.
    goto :fim_com_erro
)
for /f "delims=" %%v in ('ollama --version 2^>nul') do set "VERSAO=%%v"
echo [OK]    Ollama instalado: !VERSAO!

:: 2. Verificar serviço / API
echo.
echo [....] Testando servico em http://localhost:11434 ...
curl -sf --max-time 5 http://localhost:11434/api/version >nul 2>&1
if errorlevel 1 (
    echo [AVISO] Servico offline.
    echo         Abra o app Ollama ou execute em outro terminal:
    echo           ollama serve
    echo.
    set "SERVICO_OFFLINE=1"
) else (
    echo [OK]    Servico respondendo.
    set "SERVICO_OFFLINE=0"
)

:: 3. Verificar bind de rede
echo.
echo [....] Verificando bind da porta 11434 ...
netstat -an 2>nul | findstr ":11434" >nul 2>&1
if errorlevel 1 (
    echo [AVISO] Porta 11434 nao detectada em uso.
) else (
    netstat -an 2>nul | findstr ":11434" | findstr "0.0.0.0" >nul 2>&1
    if not errorlevel 1 (
        echo [AVISO] Porta 11434 exposta em 0.0.0.0 — acessivel externamente.
        echo         Para uso local seguro, defina OLLAMA_HOST=127.0.0.1:11434
    ) else (
        echo [OK]    Porta 11434 vinculada ao loopback.
    )
)

:: 4. Modelos instalados
if "!SERVICO_OFFLINE!"=="0" (
    echo.
    echo [....] Modelos instalados ^(ollama list^):
    ollama list 2>nul || echo         Nao foi possivel listar modelos.

    :: Alertar sobre modelos cloud
    ollama list 2>nul | findstr ":cloud" >nul 2>&1
    if not errorlevel 1 (
        echo.
        echo [AVISO] Modelos com sufixo :cloud detectados.
        echo         Use modelos locais para evitar erro 403 Forbidden.
    )
)

:: 5. Modelos na memória
echo.
echo [....] Modelos na memoria ^(ollama ps^):
ollama ps 2>nul || echo         Servico offline ou nenhum modelo carregado.

:: 6. Variáveis de ambiente relevantes
echo.
echo [....] Variaveis de ambiente:
if not "%AI_BACKEND%"==""          echo   AI_BACKEND            = %AI_BACKEND%
if     "%AI_BACKEND%"==""          echo   AI_BACKEND            = ^<nao definida^>
if not "%OLLAMA_HOST%"==""         echo   OLLAMA_HOST           = %OLLAMA_HOST%
if     "%OLLAMA_HOST%"==""         echo   OLLAMA_HOST           = ^<nao definida^>
if not "%OLLAMA_MODEL%"==""        echo   OLLAMA_MODEL          = %OLLAMA_MODEL%
if     "%OLLAMA_MODEL%"==""        echo   OLLAMA_MODEL          = ^<nao definida^>
if not "%OLLAMA_NO_CLOUD%"==""     echo   OLLAMA_NO_CLOUD       = %OLLAMA_NO_CLOUD%
if     "%OLLAMA_NO_CLOUD%"==""     echo   OLLAMA_NO_CLOUD       = ^<nao definida^>
if not "%OLLAMA_CONTEXT_LENGTH%"=="" echo   OLLAMA_CONTEXT_LENGTH = %OLLAMA_CONTEXT_LENGTH%

:: 7. GPU (apenas nvidia-smi; sem presumir hardware)
echo.
where nvidia-smi >nul 2>&1
if not errorlevel 1 (
    echo [....] GPU NVIDIA detectada:
    nvidia-smi --query-gpu=name,memory.total,memory.free,memory.used ^
        --format=csv,noheader 2>nul || echo         nvidia-smi nao retornou dados.
) else (
    echo [INFO] nvidia-smi nao encontrado.
    echo        Para GPU AMD/Intel, consulte o Gerenciador de Tarefas ^> GPU.
)

:: 8. Teste de inferência (opt-in: só se o modelo estiver instalado)
if "!SERVICO_OFFLINE!"=="1" goto :sem_inferencia

echo.
echo [....] Verificando se modelo "!MODELO!" esta instalado ...
ollama list 2>nul | findstr /b "!MODELO!" >nul 2>&1
if errorlevel 1 (
    echo [AVISO] Modelo "!MODELO!" nao esta instalado.
    echo         Para baixar ^(verifique espaco em disco antes^):
    echo           ollama pull !MODELO!
    echo         Para usar outro modelo, defina OLLAMA_MODEL antes de executar este script.
    goto :sem_inferencia
)

echo [OK]    Modelo "!MODELO!" encontrado. Executando teste de inferencia...
echo.
for /f "delims=" %%r in ('ollama run "!MODELO!" "Responda somente: teste local confirmado." 2^>nul') do (
    echo   Resposta: %%r
)
echo.
echo [....] ollama ps apos inferencia:
ollama ps 2>nul

goto :resultado

:sem_inferencia
echo [INFO] Teste de inferencia ignorado.
echo        Para testar (Prompt de Comando / cmd.exe):
echo          set OLLAMA_MODEL=qwen3:4b ^&^& scripts\Testar-Ollama-Local.cmd
echo        Para testar (PowerShell):
echo          $env:OLLAMA_MODEL="qwen3:4b"; cmd /c scripts\Testar-Ollama-Local.cmd

:resultado
echo.
echo ════════════════════════════════════════════════════════════
echo   Diagnostico concluido.
echo   Para diagnóstico completo: .\scripts\ollama-doctor.ps1
echo ════════════════════════════════════════════════════════════
echo.
goto :fim

:fim_com_erro
echo ════════════════════════════════════════════════════════════
echo   Diagnostico encerrado com erro. Corrija o problema acima.
echo ════════════════════════════════════════════════════════════
echo.

:fim
pause
endlocal

@echo off
:: Monitorar-VRAM.cmd — Monitor de VRAM e GPU durante inferência do Ollama.
:: Executa em janela separada. Pare com Ctrl+C.
:: Não instala nada, não altera configurações, não faz chamadas externas.

chcp 65001 >nul 2>&1
title Monitor VRAM — Ollama Local

set "INTERVALO=2"
set "HOST=http://127.0.0.1:11434"

echo.
echo ════════════════════════════════════════════════════
echo   Monitorar-VRAM — Ollama Local
echo   Intervalo: %INTERVALO% segundos  ^|  Ctrl+C para parar
echo ════════════════════════════════════════════════════
echo.

:: Verificar nvidia-smi
where nvidia-smi >nul 2>&1
if errorlevel 1 (
    echo [AVISO] nvidia-smi nao encontrado.
    echo         Monitoramento limitado a ollama ps.
    echo.
    goto :loop_sem_gpu
)

echo [OK] nvidia-smi disponivel — monitoramento completo.
echo.
goto :loop_com_gpu

:: ── Loop com GPU (nvidia-smi disponível) ─────────────────────────────────

:loop_com_gpu
echo ── %date% %time% ─────────────────────────────
echo.
echo [ollama ps]
ollama ps 2>nul || echo   servico offline ou nenhum modelo carregado

echo.
echo [GPU — nvidia-smi]
nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw ^
    --format=csv,noheader 2>nul || echo   nvidia-smi nao retornou dados

echo.
echo ─────────────────────────────────────────────────────
timeout /t %INTERVALO% /nobreak >nul
goto :loop_com_gpu

:: ── Loop sem GPU (só ollama ps) ───────────────────────────────────────────

:loop_sem_gpu
echo ── %date% %time% ─────────────────────────────
echo.
echo [ollama ps]
ollama ps 2>nul || echo   servico offline ou nenhum modelo carregado
echo.
echo ─────────────────────────────────────────────────────
timeout /t %INTERVALO% /nobreak >nul
goto :loop_sem_gpu

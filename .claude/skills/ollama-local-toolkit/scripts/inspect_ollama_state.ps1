# inspect_ollama_state.ps1 — Inspeciona o estado atual do Ollama no Windows.
#
# Não encerra processos, não cancela downloads, não faz chamadas externas.
# Uso: .\inspect_ollama_state.ps1 [-Tail <linhas>]
#   -Tail  número de linhas finais do log a exibir (padrão: 80)

param(
    [int]$Tail = 80
)

$ErrorActionPreference = "SilentlyContinue"

function Write-Sep  { Write-Host ("─" * 50) -ForegroundColor Cyan }
function Write-Info { param($msg) Write-Host "→ $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "✔ $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "⚠ $msg" -ForegroundColor Yellow }

Write-Sep
Write-Info "inspect_ollama_state — relatório de estado (somente leitura)"
Write-Sep

# 1. Modelos carregados na memória
Write-Host ""
Write-Info "[1] Modelos na memória (ollama ps):"
if (Get-Command ollama -ErrorAction SilentlyContinue) {
    $psOutput = ollama ps 2>$null
    if ($psOutput) {
        $psOutput | ForEach-Object { Write-Host "  $_" }

        # Interpretar colunas PROCESSOR para orientar o operador
        $psOutput | Select-Object -Skip 1 | ForEach-Object {
            if ($_ -match "100% GPU") {
                Write-Ok "  Modelo inteiramente na GPU — desempenho ótimo."
            } elseif ($_ -match "100% CPU") {
                Write-Warn "  Modelo na CPU — VRAM insuficiente ou GPU não detectada."
            } elseif ($_ -match "\d+% GPU") {
                Write-Warn "  Carregamento híbrido GPU/CPU — modelo não cabe inteiro na VRAM."
            }
        }
    } else {
        Write-Host "  (nenhum modelo carregado no momento)"
    }
} else {
    Write-Warn "Ollama não encontrado no PATH."
}

# 2. Modelos instalados
Write-Host ""
Write-Info "[2] Modelos instalados (ollama list):"
if (Get-Command ollama -ErrorAction SilentlyContinue) {
    $listOutput = ollama list 2>$null
    if ($listOutput) {
        $listOutput | ForEach-Object { Write-Host "  $_" }

        $cloudModels = $listOutput | Where-Object { $_ -match ":cloud" }
        if ($cloudModels) {
            Write-Warn "  Modelos com sufixo ':cloud' detectados:"
            $cloudModels | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
        }
    } else {
        Write-Host "  (nenhum modelo instalado ou serviço offline)"
    }
} else {
    Write-Warn "Ollama não encontrado no PATH."
}

# 3. Processos Ollama
Write-Host ""
Write-Info "[3] Processos Ollama em execução:"
$ollamaProcs = Get-Process -Name "ollama*" -ErrorAction SilentlyContinue
if ($ollamaProcs) {
    $ollamaProcs | Format-Table Id, ProcessName, CPU, WorkingSet, StartTime -AutoSize |
        Out-String | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ } |
        ForEach-Object { Write-Host "  $_" }

    # Detectar download em curso: ollama_runner ou múltiplas instâncias
    $runnerProcs = $ollamaProcs | Where-Object { $_.ProcessName -match "runner" }
    if ($runnerProcs) {
        Write-Ok "  ollama_runner ativo — inferência ou preparação de modelo em curso."
    }
    if (($ollamaProcs | Measure-Object).Count -gt 1) {
        Write-Info "  Múltiplos processos Ollama — pode indicar download de atualização."
    }
} else {
    Write-Warn "Nenhum processo Ollama encontrado."
}

# 4. Fim dos logs do servidor
Write-Host ""
Write-Info "[4] Últimas $Tail linhas do log do servidor Ollama:"

$logCandidates = @(
    "$env:LOCALAPPDATA\Ollama\ollama.log",
    "$env:USERPROFILE\.ollama\logs\server.log",
    "$env:USERPROFILE\AppData\Local\Ollama\ollama.log"
)

$logFound = $false
foreach ($logPath in $logCandidates) {
    if (Test-Path $logPath) {
        Write-Host "  Arquivo: $logPath"
        Write-Sep
        Get-Content $logPath -Tail $Tail -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host "  $_" }
        $logFound = $true

        # Interpretar padrões comuns no log
        $recentLines = Get-Content $logPath -Tail $Tail -ErrorAction SilentlyContinue
        if ($recentLines -match "pulling|downloading|total bytes") {
            Write-Warn "  Log contém linhas de download/pull — atualização ou modelo em andamento."
            Write-Info "  Não interrompa o processo; aguarde a conclusão."
        }
        if ($recentLines -match "llama runner started|loaded in") {
            Write-Ok "  Log indica modelo carregado com sucesso."
        }
        break
    }
}

if (-not $logFound) {
    Write-Warn "Arquivo de log não encontrado nos caminhos padrão:"
    $logCandidates | ForEach-Object { Write-Host "  $_" }
    Write-Info "Verifique: Get-EventLog -LogName Application -Source '*ollama*' -Newest 20"
}

# 5. Bind de rede
Write-Host ""
Write-Info "[5] Bind de rede (porta 11434):"
$bindOutput = netstat -an 2>$null | Select-String "11434"
if ($bindOutput) {
    $bindOutput | ForEach-Object { Write-Host "  $_" }
    if ($bindOutput | Where-Object { $_ -match "0\.0\.0\.0:11434" }) {
        Write-Warn "  Porta 11434 exposta em 0.0.0.0 — acessível externamente."
        Write-Warn "  Defina OLLAMA_HOST=127.0.0.1:11434 e reinicie o serviço."
    } elseif ($bindOutput | Where-Object { $_ -match "127\.0\.0\.1:11434" }) {
        Write-Ok "  Porta 11434 vinculada apenas ao loopback."
    }
} else {
    Write-Warn "Porta 11434 não detectada — serviço pode estar inativo."
}

Write-Host ""
Write-Sep
Write-Ok "Relatório concluído. Nenhum processo foi encerrado nem modificado."

# local-ai.ps1 — Gerenciador Ollama para Windows (PowerShell)
# Uso: .\local-ai.ps1 <comando> [args]
# Comandos: doctor | list | run | ask | gpu | stop | remove | test | cloud-check | cloud-login | cloud-run

param(
    [Parameter(Position=0)] [string]$Command = "help",
    [Parameter(Position=1)] [string]$Arg1 = "",
    [Parameter(Position=2)] [string]$Arg2 = ""
)

$ErrorActionPreference = "Stop"
$OllamaHost = $env:OLLAMA_HOST ?? "http://localhost:11434"
$DefaultModel = $env:OLLAMA_DEFAULT_MODEL ?? "qwen3:4b"

# ── Helpers ──────────────────────────────────────────────────────────────────
function Write-Ok   { param($msg) Write-Host "✔ $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "⚠ $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "✖ $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "→ $msg" -ForegroundColor Cyan }

function Require-Ollama {
    if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
        Write-Err "Ollama não encontrado. Baixe em https://ollama.com/download"
        exit 1
    }
}

function Test-OllamaRunning {
    try {
        $null = Invoke-RestMethod -Uri "$OllamaHost/api/version" -TimeoutSec 3
        return $true
    } catch {
        return $false
    }
}

function Assert-OllamaRunning {
    if (-not (Test-OllamaRunning)) {
        Write-Warn "Ollama não está respondendo em $OllamaHost."
        Write-Warn "Abra o app Ollama ou rode: ollama serve"
        exit 1
    }
}

# ── Comandos ─────────────────────────────────────────────────────────────────

function Invoke-Doctor {
    Write-Info "=== Diagnóstico do ambiente Ollama ==="

    Require-Ollama
    $ver = ollama --version 2>$null
    Write-Ok "Ollama instalado: $ver"

    if (Test-OllamaRunning) {
        Write-Ok "Serviço respondendo em $OllamaHost"
        try {
            $apiVer = (Invoke-RestMethod -Uri "$OllamaHost/api/version").version
            Write-Info "Versão da API: $apiVer"
        } catch {}
    } else {
        Write-Warn "Serviço offline. Abra o app Ollama ou rode: ollama serve"
    }

    Write-Info "Modelos disponíveis localmente:"
    ollama list

    # GPU
    $nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($nvidiaSmi) {
        Write-Ok "nvidia-smi encontrado — GPU NVIDIA disponível."
        nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader 2>$null
    } else {
        Write-Warn "nvidia-smi não encontrado. Pode estar usando apenas CPU."
        Write-Info "Para GPUs AMD/Intel no Windows, veja o Gerenciador de Tarefas → GPU."
    }
}

function Invoke-List {
    Require-Ollama; Assert-OllamaRunning
    Write-Info "Modelos locais instalados:"
    ollama list
}

function Invoke-Run {
    $model = if ($Arg1) { $Arg1 } else { $DefaultModel }
    Require-Ollama; Assert-OllamaRunning
    Write-Info "Iniciando sessão interativa com: $model"
    Write-Info "Digite /bye para sair."
    ollama run $model
}

function Invoke-Ask {
    $model  = if ($Arg1) { $Arg1 } else { $DefaultModel }
    $prompt = if ($Arg2) { $Arg2 } else { "Responda somente: teste local confirmado." }
    Require-Ollama; Assert-OllamaRunning
    Write-Info "Perguntando ao modelo $model..."
    ollama run $model $prompt
}

function Invoke-Gpu {
    Write-Info "=== Uso de GPU ==="
    if (Test-OllamaRunning) {
        Write-Info "Modelos na memória (ollama ps):"
        ollama ps
    }
    $nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($nvidiaSmi) {
        Write-Info "Status GPU NVIDIA:"
        nvidia-smi
    } else {
        Write-Info "Abra o Gerenciador de Tarefas → aba Desempenho → GPU para monitorar."
    }
}

function Invoke-Stop {
    if (-not $Arg1) { Write-Err "Uso: .\local-ai.ps1 stop <modelo>"; exit 1 }
    Require-Ollama; Assert-OllamaRunning
    Write-Info "Descarregando modelo da memória: $Arg1"
    $body = @{ model = $Arg1; keep_alive = 0 } | ConvertTo-Json
    try {
        Invoke-RestMethod -Method Post -Uri "$OllamaHost/api/generate" `
            -ContentType "application/json" -Body $body | Out-Null
        Write-Ok "Solicitação enviada. Verifique com: ollama ps"
    } catch {
        Write-Warn "Resposta inesperada: $_"
    }
}

function Invoke-Remove {
    if (-not $Arg1) { Write-Err "Uso: .\local-ai.ps1 remove <modelo>"; exit 1 }
    Write-Warn "Isso apagará permanentemente o modelo '$Arg1' do disco."
    $resp = Read-Host "Confirmar remoção? [s/N]"
    if ($resp -match "^[sS]$") {
        ollama rm $Arg1
        Write-Ok "Modelo '$Arg1' removido."
    } else {
        Write-Info "Cancelado."
    }
}

function Invoke-Test {
    $model = if ($Arg1) { $Arg1 } else { $DefaultModel }
    Require-Ollama; Assert-OllamaRunning
    Write-Info "Teste rápido — modelo: $model"
    $resp = ollama run $model "Responda somente: teste local confirmado." 2>$null
    if ($resp) {
        Write-Ok "Resposta recebida:"
        Write-Host "  $resp"
    } else {
        Write-Err "Sem resposta. Verifique se o modelo está instalado com: ollama list"
        exit 1
    }
}

function Invoke-CloudCheck {
    Write-Info "=== Verificação de uso cloud ==="
    Write-Warn "Modelos cloud consomem créditos/assinatura Ollama."
    Write-Warn "Verifique seu plano em: https://ollama.com/settings/billing"
    Write-Info "Modelos com sufixo ':cloud' são executados na nuvem."
    Write-Info "Para uso apenas local, escolha modelos sem esse sufixo."
    if (Test-OllamaRunning) {
        Write-Info "Modelos locais disponíveis:"
        ollama list | Where-Object { $_ -notmatch ":cloud" }
    }
}

function Invoke-CloudLogin {
    Write-Warn "=== Login no Ollama Cloud ==="
    Write-Warn "Isso vinculará este terminal à sua conta Ollama."
    Write-Warn "Verifique seu plano antes: https://ollama.com/settings/billing"
    $resp = Read-Host "Deseja continuar com o login? [s/N]"
    if ($resp -match "^[sS]$") {
        ollama login
        Write-Ok "Login concluído."
    } else {
        Write-Info "Cancelado."
    }
}

function Invoke-CloudRun {
    if (-not $Arg1) {
        Write-Err "Uso: .\local-ai.ps1 cloud-run <modelo-cloud> [prompt]"
        exit 1
    }
    Write-Warn "=== Execução de modelo CLOUD: $Arg1 ==="
    Write-Warn "Isso pode consumir créditos da sua conta Ollama."
    $resp = Read-Host "Confirmar envio para a nuvem? [s/N]"
    if ($resp -match "^[sS]$") {
        Require-Ollama; Assert-OllamaRunning
        if ($Arg2) { ollama run $Arg1 $Arg2 } else { ollama run $Arg1 }
    } else {
        Write-Info "Cancelado. Nenhum dado enviado para a nuvem."
    }
}

function Show-Help {
    Write-Host ""
    Write-Host "Uso: .\local-ai.ps1 <comando> [args]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  doctor                 Diagnóstico completo do ambiente"
    Write-Host "  list                   Lista modelos instalados localmente"
    Write-Host "  run [modelo]           Sessão interativa"
    Write-Host "  ask [modelo] [prompt]  Pergunta rápida e sai"
    Write-Host "  gpu                    Uso de GPU e modelos na memória"
    Write-Host "  stop <modelo>          Descarrega modelo da VRAM/RAM"
    Write-Host "  remove <modelo>        Remove do disco (pede confirmação)"
    Write-Host "  test [modelo]          Teste rápido de resposta local"
    Write-Host "  cloud-check            Informa sobre modelos cloud e plano"
    Write-Host "  cloud-login            Login no Ollama Cloud (pede confirmação)"
    Write-Host "  cloud-run <mod> [p]    Envia prompt para cloud (pede confirmação)"
    Write-Host ""
    Write-Host "Variáveis de ambiente (opcional):"
    Write-Host "  OLLAMA_HOST              (padrão: http://localhost:11434)"
    Write-Host "  OLLAMA_DEFAULT_MODEL     (padrão: qwen3:4b)"
    Write-Host ""
}

# ── Roteador ─────────────────────────────────────────────────────────────────
switch ($Command) {
    "doctor"      { Invoke-Doctor }
    "list"        { Invoke-List }
    "run"         { Invoke-Run }
    "ask"         { Invoke-Ask }
    "gpu"         { Invoke-Gpu }
    "stop"        { Invoke-Stop }
    "remove"      { Invoke-Remove }
    "test"        { Invoke-Test }
    "cloud-check" { Invoke-CloudCheck }
    "cloud-login" { Invoke-CloudLogin }
    "cloud-run"   { Invoke-CloudRun }
    default       { Show-Help }
}

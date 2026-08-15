# ollama-doctor.ps1 — Diagnóstico seguro do ambiente Ollama (Windows PowerShell)
# Executa somente testes de leitura. Teste de inferência é opt-in.
# Uso: .\scripts\ollama-doctor.ps1 [-Model <modelo>]

param(
    [string]$Model = ""
)

$ErrorActionPreference = "Stop"
$OllamaHost = $env:OLLAMA_HOST ?? "http://localhost:11434"

function Write-Ok   { param($msg) Write-Host "✔ $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "⚠ $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "✖ $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "→ $msg" -ForegroundColor Cyan }
function Write-Sep  { Write-Host ("─" * 44) -ForegroundColor Cyan }

Write-Sep
Write-Info "Ollama Doctor — diagnóstico do ambiente local"
Write-Sep

# 1. Verificar instalação
if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
    Write-Err "Ollama não encontrado. Instale em: https://ollama.com/download"
    exit 1
}
$version = ollama --version 2>$null
Write-Ok "Ollama instalado: $version"

# 2. Verificar serviço
Write-Info "Testando serviço em $OllamaHost..."
$serviceOnline = $false
try {
    $apiInfo = Invoke-RestMethod -Uri "$OllamaHost/api/version" -TimeoutSec 5
    Write-Ok "Serviço respondendo. API versão: $($apiInfo.version)"
    $serviceOnline = $true
} catch {
    Write-Warn "Serviço offline em $OllamaHost."
    Write-Warn "Abra o app Ollama ou execute: ollama serve (em outro terminal)"
}

# 3. Modelos instalados
if ($serviceOnline) {
    Write-Sep
    Write-Info "Modelos instalados localmente:"
    $modelList = ollama list 2>$null
    $modelList | ForEach-Object { Write-Host "  $_" }

    $cloudCount = ($modelList | Where-Object { $_ -match ":cloud" } | Measure-Object).Count
    if ($cloudCount -gt 0) {
        Write-Warn "$cloudCount modelo(s) com sufixo ':cloud' detectado(s). Use modelos locais para evitar erro 403."
    }
}

# 4. Modelos na memória
Write-Sep
Write-Info "Modelos atualmente na memória (ollama ps):"
try {
    ollama ps 2>$null | ForEach-Object { Write-Host "  $_" }
} catch {
    Write-Warn "Não foi possível executar ollama ps."
}

# 5. Variáveis de ambiente
Write-Sep
Write-Info "Variáveis de ambiente relevantes:"
$vars = @("AI_BACKEND", "OLLAMA_HOST", "OLLAMA_MODEL", "OLLAMA_NO_CLOUD", "OLLAMA_CONTEXT_LENGTH")
foreach ($v in $vars) {
    $val = [System.Environment]::GetEnvironmentVariable($v) ?? "<não definida>"
    Write-Host "  ${v}=${val}"
}

# 6. GPU — detectar sem presumir Nvidia
Write-Sep
Write-Info "Detecção de GPU:"
$nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nvidiaSmi) {
    Write-Ok "nvidia-smi encontrado — GPU NVIDIA disponível."
    nvidia-smi --query-gpu=name,memory.total,memory.free,memory.used --format=csv,noheader 2>$null `
        | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Warn "nvidia-smi não encontrado."
    Write-Info "Para GPUs AMD/Intel no Windows, verifique o Gerenciador de Tarefas → Desempenho → GPU."
    Write-Info "Instale CUDA (Nvidia) ou ROCm (AMD) para habilitar suporte a GPU no Ollama."
}

# 7. CPU e RAM
Write-Sep
Write-Info "CPU e memória:"
$cpuInfo = Get-CimInstance Win32_Processor | Select-Object -First 1
Write-Host "  CPU: $($cpuInfo.Name)"
Write-Host "  Núcleos lógicos: $($cpuInfo.NumberOfLogicalProcessors)"
$ramInfo = Get-CimInstance Win32_OperatingSystem
$ramTotalGB  = [math]::Round($ramInfo.TotalVisibleMemorySize / 1MB, 1)
$ramFreeGB   = [math]::Round($ramInfo.FreePhysicalMemory     / 1MB, 1)
Write-Host "  RAM total: ${ramTotalGB} GB | disponível: ${ramFreeGB} GB"

# 8. Teste de inferência (opt-in)
Write-Sep
if ($Model) {
    Write-Info "Teste de inferência com modelo: $Model"
    $installedModels = ollama list 2>$null | Where-Object { $_ -match "^$([regex]::Escape($Model))" }
    if ($installedModels) {
        try {
            $resp = ollama run $Model "Responda somente: teste local confirmado." 2>$null
            if ($resp) {
                Write-Ok "Resposta recebida: $resp"
            } else {
                Write-Warn "Resposta vazia ou erro durante a inferência."
            }
        } catch {
            Write-Warn "Erro na inferência: $_"
        }
        Write-Info "ollama ps após inferência:"
        ollama ps 2>$null | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Warn "Modelo '$Model' não está instalado."
        Write-Warn "Liste modelos com: ollama list"
        Write-Warn "Para baixar (verifique espaço antes): ollama pull $Model"
    }
} else {
    Write-Info "Teste de inferência ignorado (passe -Model <modelo> para ativar)."
    Write-Info "Exemplo: .\scripts\ollama-doctor.ps1 -Model qwen3:4b"
}

Write-Sep
Write-Ok "Diagnóstico concluído."

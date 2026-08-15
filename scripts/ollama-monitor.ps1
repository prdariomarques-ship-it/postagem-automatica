# ollama-monitor.ps1 — Monitoramento local de desempenho do Ollama (Windows)
# Sem serviços em nuvem, sem dependências Python externas.
#
# Uso:
#   .\scripts\ollama-monitor.ps1 [-Intervalo <seg>] [-Log] [-Modelo <tag>] [-Duracao <seg>]

param(
    [int]   $Intervalo = 2,
    [switch]$Log,
    [string]$Modelo = "",
    [int]   $Duracao = 0
)

$ErrorActionPreference = "Stop"
$OllamaHost = $env:OLLAMA_HOST ?? "http://localhost:11434"

# ── Verificar Ollama ──────────────────────────────────────────────────────────
if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
    Write-Host "ERRO: ollama não encontrado. Instale em: https://ollama.com/download" -ForegroundColor Red
    exit 1
}

# ── Detectar GPU ──────────────────────────────────────────────────────────────
$GpuType = "none"
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) { $GpuType = "nvidia" }

# ── Arquivo de log ────────────────────────────────────────────────────────────
$LogFile = $null
if ($Log) {
    $logsDir = Join-Path $PSScriptRoot "..\logs"
    New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $LogFile = Join-Path $logsDir "ollama-monitor-$ts.csv"
    "datetime,ollama_model,processor,gpu_util_pct,vram_used_mb,vram_total_mb,cpu_pct,ram_avail_mb,session_model" |
        Out-File -FilePath $LogFile -Encoding UTF8
    Write-Host "Log CSV: $LogFile" -ForegroundColor Cyan
}

# ── Coletar linha ─────────────────────────────────────────────────────────────
function Get-DataLine {
    $dt = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    $modelCol = ""; $procCol = ""
    $gpuUtil = "indisponivel"; $vramUsed = "indisponivel"; $vramTotal = "indisponivel"
    $cpuPct = ""; $ramAvail = ""

    # ollama ps
    try {
        $psLines = ollama ps 2>$null | Select-Object -Skip 1 | Select-Object -First 1
        if ($psLines) {
            $parts = $psLines -split '\s+', 8
            if ($parts.Count -ge 1) { $modelCol = $parts[0] }
            $procMatch = $psLines | Select-String -Pattern '\d+%\s+\w+' -AllMatches
            if ($procMatch.Matches.Count -gt 0) {
                $procCol = ($procMatch.Matches | ForEach-Object { $_.Value }) -join " / "
            }
        }
    } catch {}

    # GPU
    if ($GpuType -eq "nvidia") {
        try {
            $nvLine = nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total `
                --format=csv,noheader,nounits 2>$null | Select-Object -First 1
            if ($nvLine) {
                $nvParts = $nvLine -split ',\s*'
                $gpuUtil  = $nvParts[0].Trim()
                $vramUsed = $nvParts[1].Trim()
                $vramTotal= $nvParts[2].Trim()
            }
        } catch {}
    }

    # CPU (% via CIM — 1 sample)
    try {
        $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        $cpuPct  = [math]::Round($cpuLoad, 0)
    } catch {}

    # RAM disponível (MB)
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $ramAvail = [math]::Round($os.FreePhysicalMemory / 1KB, 0)
    } catch {}

    # Saída formatada
    Write-Host ("{0} | modelo: {1,-20} proc: {2,-20} gpu: {3,4}% vram: {4}/{5} MB cpu: {6}% ram: {7} MB" -f `
        $dt, $(if($modelCol){"$modelCol"}else{"<idle>"}), $procCol, `
        $gpuUtil, $vramUsed, $vramTotal, $cpuPct, $ramAvail)

    if ($LogFile) {
        "$dt,$modelCol,$procCol,$gpuUtil,$vramUsed,$vramTotal,$cpuPct,$ramAvail,$Modelo" |
            Out-File -FilePath $LogFile -Append -Encoding UTF8
    }
}

# ── Cabeçalho ─────────────────────────────────────────────────────────────────
Write-Host ("━" * 60) -ForegroundColor Cyan
Write-Host "Ollama Monitor  intervalo: ${Intervalo}s  GPU: $GpuType  Ctrl+C para parar" -ForegroundColor Cyan
if ($Modelo) { Write-Host "  Sessão: $Modelo" -ForegroundColor Cyan }
if ($Duracao -gt 0) { Write-Host "  Duração: ${Duracao}s" -ForegroundColor Cyan }
Write-Host ""

# ── Loop principal ────────────────────────────────────────────────────────────
$start = Get-Date
try {
    while ($true) {
        Get-DataLine

        if ($Duracao -gt 0) {
            $elapsed = ((Get-Date) - $start).TotalSeconds
            if ($elapsed -ge $Duracao) {
                Write-Host ""
                Write-Host "Duração atingida (${Duracao}s). Encerrando." -ForegroundColor Green
                break
            }
        }

        Start-Sleep -Seconds $Intervalo
    }
} catch [System.Management.Automation.PipelineStoppedException] {
    # Ctrl+C normal
}

if ($LogFile) {
    Write-Host "CSV salvo em: $LogFile" -ForegroundColor Green
}

# Ollama-Local.ps1 — Interface portátil para Ollama local (Windows)
# Usa exclusivamente http://127.0.0.1:11434. Sem nuvem, sem chaves de API.
# Abra via Abrir-Ollama-Local.cmd ou: PowerShell -ExecutionPolicy Bypass -File Ollama-Local.ps1

$ErrorActionPreference = "SilentlyContinue"
$OLLAMA_HOST = "http://127.0.0.1:11434"
$script:ModeloAtual = if ($env:OLLAMA_MODEL) { $env:OLLAMA_MODEL } else { "" }

# ── Funções de saída ──────────────────────────────────────────────────────

function Write-Sep  { Write-Host ("═" * 51) -ForegroundColor Cyan }
function Write-Info { param($m) Write-Host "  → $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "  ✔ $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  ⚠ $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  ✖ $m" -ForegroundColor Red }

# ── Verificar serviço ─────────────────────────────────────────────────────

function Test-OllamaOnline {
    try {
        $null = Invoke-RestMethod -Uri "$OLLAMA_HOST/api/version" -TimeoutSec 5
        return $true
    } catch { return $false }
}

# ── Menu principal ────────────────────────────────────────────────────────

function Show-Menu {
    Clear-Host
    Write-Sep
    Write-Host "  Ollama Local — Interface Portátil" -ForegroundColor Cyan
    Write-Host "  $OLLAMA_HOST" -ForegroundColor DarkGray
    Write-Sep
    if ($script:ModeloAtual) {
        Write-Host "  Modelo : $($script:ModeloAtual)" -ForegroundColor Green
    } else {
        Write-Host "  Modelo : (nenhum selecionado — use [2])" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  [1] Enviar prompt" -ForegroundColor White
    Write-Host "  [2] Selecionar modelo" -ForegroundColor White
    Write-Host "  [3] Importar GGUF local" -ForegroundColor White
    Write-Host "  [4] Liberar VRAM" -ForegroundColor White
    Write-Host "  [5] Diagnóstico (ollama ps)" -ForegroundColor White
    Write-Host "  [0] Sair" -ForegroundColor DarkGray
    Write-Sep
    Write-Host -NoNewline "  Escolha: "
}

# ── Opção 1: Enviar prompt ────────────────────────────────────────────────

function Send-Prompt {
    if (-not $script:ModeloAtual) {
        Write-Warn "Nenhum modelo selecionado. Use [2] primeiro."
        return
    }
    Write-Host ""
    Write-Host -NoNewline "  Prompt: " -ForegroundColor Cyan
    $userPrompt = Read-Host
    if (-not $userPrompt.Trim()) { Write-Warn "Prompt vazio."; return }

    Write-Info "Aguardando resposta de '$($script:ModeloAtual)'..."
    $body = @{
        model   = $script:ModeloAtual
        prompt  = $userPrompt
        stream  = $false
        options = @{ num_ctx = [int]($env:OLLAMA_CONTEXT_LENGTH ?? "4096") }
    } | ConvertTo-Json -Compress

    try {
        $resp = Invoke-RestMethod -Uri "$OLLAMA_HOST/api/generate" `
            -Method POST -Body $body -ContentType "application/json" -TimeoutSec 120
        Write-Host ""
        Write-Host "  ── Resposta ─────────────────────────────────" -ForegroundColor DarkCyan
        $resp.response.Trim() -split "`n" | ForEach-Object { Write-Host "  $_" }
        Write-Host "  ─────────────────────────────────────────────" -ForegroundColor DarkCyan
    } catch {
        Write-Err "Erro ao chamar API: $_"
        Write-Warn "Verifique se o serviço está ativo: ollama serve"
    }
}

# ── Opção 2: Selecionar modelo ────────────────────────────────────────────

function Select-Model {
    Write-Host ""
    Write-Info "Modelos instalados:"
    $lista = ollama list 2>$null
    if (-not $lista) { Write-Warn "Nenhum modelo instalado ou serviço offline."; return }

    $modelos = @()
    $lista | Select-Object -Skip 1 | ForEach-Object {
        $nome = ($_ -split '\s+')[0]
        if ($nome) { $modelos += $nome }
    }

    if ($modelos.Count -eq 0) { Write-Warn "Nenhum modelo encontrado."; return }

    for ($i = 0; $i -lt $modelos.Count; $i++) {
        $marca = if ($modelos[$i] -match ":cloud") { " ⚠ cloud" } else { "" }
        Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $modelos[$i], $marca) -ForegroundColor $(
            if ($modelos[$i] -match ":cloud") { "Yellow" } else { "White" }
        )
    }

    Write-Host -NoNewline "`n  Número do modelo (0 = cancelar): "
    $escolha = Read-Host
    if ($escolha -eq "0" -or -not $escolha) { return }
    $idx = [int]$escolha - 1
    if ($idx -lt 0 -or $idx -ge $modelos.Count) { Write-Warn "Opção inválida."; return }

    $nome = $modelos[$idx]
    if ($nome -match ":cloud") {
        Write-Err "Modelos ':cloud' são bloqueados nesta interface. Escolha outro."
        return
    }
    $script:ModeloAtual = $nome
    Write-Ok "Modelo selecionado: $($script:ModeloAtual)"
}

# ── Opção 3: Importar GGUF local ──────────────────────────────────────────

function Import-GGUF {
    Write-Host ""
    Write-Warn "Este processo cria um modelo a partir de um arquivo .gguf local."
    Write-Warn "Pode levar vários minutos dependendo do tamanho do arquivo."
    Write-Host ""
    Write-Host -NoNewline "  Caminho completo do arquivo .gguf (0 = cancelar): "
    $ggufPath = (Read-Host).Trim('"').Trim()
    if ($ggufPath -eq "0" -or -not $ggufPath) { return }

    if (-not (Test-Path $ggufPath)) {
        Write-Err "Arquivo não encontrado: $ggufPath"
        return
    }
    if (-not $ggufPath.ToLower().EndsWith(".gguf")) {
        Write-Err "O arquivo não termina em .gguf. Operação cancelada."
        return
    }

    $info = Get-Item $ggufPath
    Write-Ok "Arquivo encontrado: $($info.Name) ($([math]::Round($info.Length/1GB,2)) GB)"

    Write-Host -NoNewline "  Nome local para o modelo (ex: meu-modelo:q4): "
    $localName = (Read-Host).Trim()
    if (-not $localName) { Write-Warn "Nome não informado. Cancelado."; return }
    if ($localName -match ":cloud|-cloud") {
        Write-Err "Nome não pode conter ':cloud' ou '-cloud'."
        return
    }

    Write-Info "Criando modelo '$localName' a partir de '$($info.Name)'..."
    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tempFile -Value "FROM $ggufPath" -Encoding UTF8
        ollama create $localName -f $tempFile
        $exitCode = $LASTEXITCODE
    } finally {
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }

    if ($exitCode -eq 0) {
        Write-Ok "Modelo '$localName' criado com sucesso."
        Write-Info "Verificando com: ollama list"
        ollama list 2>$null | Select-String $localName | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Err "Falha ao criar modelo (código $exitCode). Verifique o caminho e o formato do arquivo."
    }
}

# ── Opção 4: Liberar VRAM ─────────────────────────────────────────────────

function Release-VRAM {
    Write-Host ""
    Write-Info "Modelos na memória (ollama ps):"
    $psOutput = ollama ps 2>$null
    $loadedModels = $psOutput | Select-Object -Skip 1 |
        ForEach-Object { ($_ -split '\s+')[0] } |
        Where-Object { $_ -and $_ -ne "" }

    if (-not $loadedModels) {
        Write-Ok "Nenhum modelo carregado na memória."
        return
    }

    foreach ($m in $loadedModels) {
        Write-Info "Parando modelo: $m"
        ollama stop $m 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "$m removido da memória."
        } else {
            Write-Warn "Não foi possível parar '$m' via CLI. Tentando via API..."
            $body = @{ model = $m; keep_alive = "0" } | ConvertTo-Json -Compress
            try {
                Invoke-RestMethod -Uri "$OLLAMA_HOST/api/generate" `
                    -Method POST -Body $body -ContentType "application/json" -TimeoutSec 15 | Out-Null
                Write-Ok "$m descarregado via API."
            } catch { Write-Warn "Falha ao descarregar '$m'." }
        }
    }

    Write-Host ""
    Write-Info "ollama ps após liberação:"
    ollama ps 2>$null | ForEach-Object { Write-Host "  $_" }
}

# ── Opção 5: Diagnóstico ──────────────────────────────────────────────────

function Show-Diagnostics {
    Write-Host ""
    Write-Info "ollama ps:"
    $ps = ollama ps 2>$null
    if ($ps) {
        $ps | ForEach-Object { Write-Host "  $_" }
        $ps | Select-Object -Skip 1 | ForEach-Object {
            if ($_ -match "100% GPU")          { Write-Ok  "GPU integral — ótimo." }
            elseif ($_ -match "100% CPU")      { Write-Warn "Modelo na CPU — VRAM insuficiente ou GPU não detectada." }
            elseif ($_ -match "\d+% GPU")      { Write-Warn "Carregamento híbrido GPU/CPU." }
        }
    } else { Write-Host "  (nenhum modelo carregado ou serviço offline)" }

    Write-Host ""
    Write-Info "Endpoint: $OLLAMA_HOST"
    if (Test-OllamaOnline) { Write-Ok "Serviço respondendo." }
    else                   { Write-Warn "Serviço offline." }

    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Info "GPU NVIDIA:"
        nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu `
            --format=csv,noheader 2>$null | ForEach-Object { Write-Host "  $_" }
    }
}

# ── Loop principal ────────────────────────────────────────────────────────

if (-not (Test-OllamaOnline)) {
    Write-Warn "Serviço Ollama não encontrado em $OLLAMA_HOST."
    Write-Warn "Inicie o Ollama antes de usar esta interface."
    Write-Host "  Pressione Enter para continuar mesmo assim..."
    $null = Read-Host
}

$continuar = $true
while ($continuar) {
    Show-Menu
    $opcao = Read-Host

    switch ($opcao.Trim()) {
        "1" { Send-Prompt }
        "2" { Select-Model }
        "3" { Import-GGUF }
        "4" { Release-VRAM }
        "5" { Show-Diagnostics }
        "0" { $continuar = $false; break }
        default { Write-Warn "Opção inválida: '$opcao'" }
    }

    if ($continuar) {
        Write-Host ""
        Write-Host "  Pressione Enter para voltar ao menu..." -ForegroundColor DarkGray
        $null = Read-Host
    }
}

Write-Host ""
Write-Ok "Interface encerrada. O serviço Ollama continua ativo."
Write-Host ""

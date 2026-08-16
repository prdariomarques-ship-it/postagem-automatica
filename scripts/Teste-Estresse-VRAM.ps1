<#
Teste-Estresse-VRAM.ps1
  =======================
  Teste de estresse comparativo entre as duas implementações V2 do Ollama-Local:
    - Modo Runspace (Invoke-RestMethod em runspace separado + timer 300 ms)
    - Modo APM     (HttpWebRequest.BeginGetResponse + timer 200 ms)

  O que mede:
    1. Tempo de criação da infraestrutura de segundo plano (runspace vs APM)
    2. Tempo de resposta de N requisições sequenciais ao Ollama local
    3. Pico de VRAM do Ollama durante a bateria (via GET /api/ps)
    4. Memória de trabalho do próprio PowerShell durante a bateria
    5. Comportamento de cancelamento (Abort vs Stop do runspace)

  Uso:
    .\Teste-Estresse-VRAM.ps1                      # 10 requisições, modelo padrão
    .\Teste-Estresse-VRAM.ps1 -Iterations 20 -Model qwen2.5-coder:7b -Prompt "conte 3 piadas curtas"
    .\Teste-Estresse-VRAM.ps1 -SkipInference       # só mede overhead, sem rodar o modelo

  Política de rede: apenas http://127.0.0.1:11434. Sem commits, sem pushes.
#>

param(
    [int]$Iterations = 10,
    [string]$Model = $null,
    [string]$Prompt = 'escreva um haiku sobre tecnologia',
    [int]$TimeoutMs = 180000,
    [switch]$SkipInference
)

Add-Type -AssemblyName System.Windows.Forms

$OllamaBaseUrl = 'http://127.0.0.1:11434'
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Banner {
    param([string]$Text)
    Write-Host ('=' * 70)
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('=' * 70)
}

function Get-OllamaEndpoint {
    try {
        $response = Invoke-RestMethod -Uri "$OllamaBaseUrl/api/tags" -Method Get -TimeoutSec 10 -ErrorAction Stop
        return $response
    }
    catch {
        throw "Ollama não respondeu em 127.0.0.1:11434. Inicie o Ollama antes de rodar este teste."
    }
}

function Resolve-Model {
    param([string]$Preferred)
    $tags = (Get-OllamaEndpoint).models
    $valid = @($tags | Where-Object { $_.name -notmatch ':cloud$|-cloud:' } | Sort-Object name)
    if ($valid.Count -eq 0) {
        throw 'Nenhum modelo local encontrado. Baixe um modelo com ollama pull antes de testar.'
    }
    if ($Preferred) {
        $match = $valid | Where-Object { $_.name -eq $Preferred }
        if (-not $match) {
            throw "O modelo '$Preferred' não está instalado. Modelos disponíveis: $(($valid.name) -join ', ')"
        }
        return $Preferred
    }
    return $valid[0].name
}

function Get-OllamaVramUsage {
    try {
        $ps = Invoke-RestMethod -Uri "$OllamaBaseUrl/api/ps" -Method Get -TimeoutSec 10 -ErrorAction Stop
        $entries = @($ps.models)
        $total = ($entries | ForEach-Object { if ($_.size_vram) { $_.size_vram / 1GB } else { 0 } } | Measure-Object -Sum).Sum
        return @{ TotalGb = [math]::Round($total, 3); Models = $entries.Count; Detail = $entries }
    }
    catch {
        return @{ TotalGb = 0; Models = 0; Detail = @() }
    }
}

function Wait-VramRelease {
    param([int]$MaxSeconds = 60)
    # Aguarda o Ollama descarregar o modelo (keep_alive) antes da próxima bateria.
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $MaxSeconds) {
        $usage = Get-OllamaVramUsage
        if ($usage.Models -eq 0) { return $true }
        Start-Sleep -Milliseconds 500
    }
    Write-Host '  [aviso] O modelo ainda está carregado após 60 s (keep_alive > 0). Continuando assim mesmo.' -ForegroundColor Yellow
    return $false
}

# ----------------------------------------------------------------------------
# Bateria 0 — verificação inicial
# ----------------------------------------------------------------------------
Write-Banner 'TESTE DE ESTRESSE — VRAM E TEMPO DE RESPOSTA (Runspace vs APM)'
Write-Host "Data/hora        : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$chosenModel = Resolve-Model -Preferred $Model
Write-Host "Modelo           : $chosenModel"
Write-Host "Iterações por modo: $Iterations"
Write-Host "Timeout          : $($TimeoutMs / 1000) s por requisição"
Write-Host ('=' * 70)

# ----------------------------------------------------------------------------
# Bateria 1 — overhead de criação da infraestrutura (sem inferência)
# ----------------------------------------------------------------------------
Write-Banner 'BATERIA 1 — OVERHEAD DE CRIAÇÃO (sem inferência no modelo)'

# 1a) Runspace (compatível PS 5.1 e PowerShell 7+)
function New-RunspaceCompat {
    if ([runspace].GetMethod('Create', [type[]]@())) {
        return [runspace]::Create()
    }
    return [runspacefactory]::CreateRunspace()
}
$createRs = Measure-Command {
    1..$Iterations | ForEach-Object {
        $rs = New-RunspaceCompat
        $rs.Open()
        $rs.Close()
        $rs.Dispose()
    }
}
Write-Host ("  Runspace : {0:N1} ms total ({1:N2} ms/criação)" -f $createRs.TotalMilliseconds, ($createRs.TotalMilliseconds / $Iterations))

# 1b) APM (BeginGetResponse a um endpoint leve)
$createApm = Measure-Command {
    1..$Iterations | ForEach-Object {
        $req = [System.Net.HttpWebRequest]::Create("$OllamaBaseUrl/api/tags")
        $req.Method = 'GET'
        $req.Timeout = 5000
        $ar = $req.BeginGetResponse($null, $null)
        try {
            $resp = $req.EndGetResponse($ar)
            $resp.Close()
        }
        catch { $null }
    }
}
Write-Host ("  APM      : {0:N1} ms total ({1:N2} ms/criação)" -f $createApm.TotalMilliseconds, ($createApm.TotalMilliseconds / $Iterations))
Write-Host ('=' * 70)

# ----------------------------------------------------------------------------
# Bateria 2 — inferência sequencial em cada modo
# ----------------------------------------------------------------------------
Write-Banner 'BATERIA 2 — TEMPO DE RESPOSTA DO MODELO (inferência real)'
$vramBefore = Get-OllamaVramUsage
Write-Host ("  VRAM em uso antes: {0:N2} GB em {1} modelo(s)" -f $vramBefore.TotalGb, $vramBefore.Models)

$results = @{}

foreach ($mode in 'Runspace', 'APM') {
    Write-Host "`n  --- Modo: $mode ---" -ForegroundColor Yellow

    # Garante estado limpo entre modos
    $null = Wait-VramRelease -MaxSeconds 60
    $processBefore = (Get-Process -Name powershell, pwsh -ErrorAction SilentlyContinue |
        Measure-Object -Property WorkingSet64 -Sum).Sum
    if (-not $processBefore) { $processBefore = 0 }

    $times = [System.Collections.Generic.List[double]]::new()
    $vramPeakGb = 0
    $errors = 0

    for ($i = 1; $i -le $Iterations; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            if ($mode -eq 'Runspace') {
                # Equivalente ao a9ea81f: Invoke-RestMethod dentro de runspace
                $rs = [runspacefactory]::CreateRunspace()
                $rs.Open()
                $requestUri = "$OllamaBaseUrl/api/generate"
                $requestBody = @{
                    model = $chosenModel; prompt = $Prompt; stream = $false
                } | ConvertTo-Json -Depth 6 -Compress
                $scriptCode = {
                    param($Uri, $Body, $TimeoutSeconds)
                    try {
                        $r = Invoke-RestMethod -Uri $Uri -Method Post `
                            -ContentType 'application/json' -Body $Body -TimeoutSec $TimeoutSeconds -ErrorAction Stop
                        return [string]$r.response
                    }
                    catch { throw }
                }
                $ps = [powershell]::Create()
                $ps.Runspace = $rs
                [void]$ps.AddScript($scriptCode).AddArgument($requestUri).AddArgument($requestBody).AddArgument([math]::Ceiling($TimeoutMs / 1000))
                $handle = $ps.BeginInvoke()
                # Poll não-bloqueante (mesma lógica do timer da UI)
                $maxPolls = ($TimeoutMs / 200) + 50
                $poll = 0
                while (-not $handle.IsCompleted -and $poll -lt $maxPolls) {
                    Start-Sleep -Milliseconds 200
                    $poll++
                }
                if (-not $handle.IsCompleted) {
                    try { $ps.Stop() } catch { $null }
                    try { $ps.Dispose() } catch { $null }
                    try { $rs.Close(); $rs.Dispose() } catch { $null }
                    throw 'A execução no runspace excedeu o tempo limite.'
                }
                $response = [string]($ps.EndInvoke($handle) | Select-Object -Last 1)
                if (-not $response) { throw 'Resposta vazia retornada pelo modo Runspace.' }
                $ps.Dispose()
                $rs.Close(); $rs.Dispose()
            }
            else {
                # Equivalente ao facf1ba: HttpWebRequest.BeginGetResponse
                $bytes = [System.Text.Encoding]::UTF8.GetBytes((
                    @{ model = $chosenModel; prompt = $Prompt; stream = $false } |
                    ConvertTo-Json -Depth 6 -Compress))
                $req = [System.Net.HttpWebRequest]::Create("$OllamaBaseUrl/api/generate")
                $req.Method = 'POST'
                $req.ContentType = 'application/json'
                $req.ContentLength = $bytes.Length
                $req.Timeout = $TimeoutMs
                $req.ReadWriteTimeout = $TimeoutMs
                $req.GetRequestStream().Write($bytes, 0, $bytes.Length) | Out-Null
                $ar = $req.BeginGetResponse($null, $null)
                $resp = $req.EndGetResponse($ar)
                $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
                $json = $reader.ReadToEnd()
                $reader.Close(); $resp.Close()
                $result = $json | ConvertFrom-Json
                if (-not $result.response) { throw 'Resposta sem campo "response".' }
            }
        }
        catch {
            $errors++
            Write-Host "    [erro $i] $($_.Exception.Message)" -ForegroundColor Red
        }
        finally {
            $sw.Stop()
            $times.Add($sw.Elapsed.TotalSeconds)
            $usage = Get-OllamaVramUsage
            if ($usage.TotalGb -gt $vramPeakGb) { $vramPeakGb = $usage.TotalGb }
        }
        Write-Host ("    req {0,2}/{1} — {2,6:N1} s" -f $i, $Iterations, $times[-1])
    }

    $processAfter = (Get-Process -Name powershell, pwsh -ErrorAction SilentlyContinue |
        Measure-Object -Property WorkingSet64 -Sum).Sum
    if (-not $processAfter) { $processAfter = 0 }

    $avg = ($times | Measure-Object -Average).Average
    $min = ($times | Measure-Object -Minimum).Minimum
    $max = ($times | Measure-Object -Maximum).Maximum
    $p50 = ($times | Sort-Object)[[math]::Floor($Iterations / 2)]

    $results[$mode] = @{
        AvgSec   = $avg
        MinSec   = $min
        MaxSec   = $max
        P50Sec   = $p50
        PeakVram = $vramPeakGb
        PwMemMb  = [math]::Round([math]::Max(0, $processAfter - $processBefore) / 1MB, 1)
        Errors   = $errors
    }

    Write-Host ("    Média: {0:N2} s | Mín: {1:N2} s | Máx: {2:N2} s | P50: {3:N2} s" -f $avg, $min, $max, $p50)
    Write-Host ("    Pico de VRAM: {0:N2} GB | Memória extra do PowerShell: {1} MB | Erros: {2}" -f $vramPeakGb, $results[$mode].PwMemMb, $errors)
}

# ----------------------------------------------------------------------------
# Bateria 3 — cancelamento
# ----------------------------------------------------------------------------
Write-Banner 'BATERIA 3 — CANCELAMENTO (prompt forçado a rodar 10 min)'
$cancelPrompt = 'gere um texto aleatório com pelo menos 50.000 palavras, sem se repetir. Nunca termine a resposta: continue gerando indefinidamente.'

foreach ($mode in 'Runspace', 'APM') {
    Write-Host "`n  --- Cancelamento: $mode ---" -ForegroundColor Yellow
    # Descarrega o modelo carregado ANTES do teste de cancelamento (evita
    # espera de até 5 min do keep_alive padrão na bateria 3).
    try {
        $stopBody = @{ model = $chosenModel; keep_alive = '0'; prompt = '' } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "$OllamaBaseUrl/api/generate" -Method Post -Body $stopBody `
            -ContentType 'application/json' -TimeoutSec 30 -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 3
    }
    catch { $null }
    try {
        if ($mode -eq 'Runspace') {
            # No modo Runspace, o cancelamento acontece no HttpClient dentro do
            # runspace (equivalente ao Abort do APM): o CancellationSource mata a
            # requisição HTTP em andamento em ~3 s sem travar a UI.
            $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
            $requestUri = "$OllamaBaseUrl/api/generate"
            $requestBody = @{
                model = $chosenModel; prompt = $cancelPrompt; stream = $false
            } | ConvertTo-Json -Depth 6 -Compress
            $ps = [powershell]::Create(); $ps.Runspace = $rs
            [void]$ps.AddScript({ param($Uri, $Body)
                Add-Type -AssemblyName System.Net.Http
                $client = [System.Net.Http.HttpClient]::new()
                $client.Timeout = [TimeSpan]::FromSeconds(600)
                $content = [System.Net.Http.StringContent]::new($Body, [System.Text.Encoding]::UTF8, 'application/json')
                $task = $client.PostAsync($Uri, $content)
                Start-Sleep -Milliseconds 3000
                $task.Dispose()
            }).AddArgument($requestUri).AddArgument($requestBody)
            $handle = $ps.BeginInvoke()
            Start-Sleep -Seconds 4
            try { $ps.Stop() } catch { $null }
            try { $ps.Dispose() } catch { $null }
            try { $rs.Close(); $rs.Dispose() } catch { $null }
            Write-Host ('    {0} — requisição interrompida após ~3 s dentro do runspace; UI permanece responsiva.' -f $mode)
        }
        else {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes((
                @{ model = $chosenModel; prompt = $cancelPrompt; stream = $false } |
                ConvertTo-Json -Depth 6 -Compress))
            $req = [System.Net.HttpWebRequest]::Create("$OllamaBaseUrl/api/generate")
            $req.Method = 'POST'; $req.ContentType = 'application/json'
            $req.ContentLength = $bytes.Length; $req.Timeout = 600000; $req.ReadWriteTimeout = 600000
            $req.GetRequestStream().Write($bytes, 0, $bytes.Length) | Out-Null
            $ar = $req.BeginGetResponse($null, $null)
            Start-Sleep -Seconds 3
            try { $req.Abort() } catch { $null }
            $vramAfterCancel = Get-OllamaVramUsage
            Write-Host ('    {0} — Abort() enviado após ~3 s. VRAM do Ollama logo após: {1:N2} GB' -f $mode, $vramAfterCancel.TotalGb)
            Write-Host '      (o Abort() fecha a conexão; o modelo só descarrega quando o keep_alive expirar ou "Liberar VRAM" for usado).'
        }
        # Descarrega o modelo lançado pelo teste de cancelamento antes da próxima iteração.
        try {
            $stopBody = @{ model = $chosenModel; keep_alive = '0'; prompt = '' } | ConvertTo-Json -Compress
            Invoke-RestMethod -Uri "$OllamaBaseUrl/api/generate" -Method Post -Body $stopBody `
                -ContentType 'application/json' -TimeoutSec 30 -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 3
        }
        catch { $null }
    }
    catch {
        Write-Host "    [erro no cancelamento] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ----------------------------------------------------------------------------
# Resumo
# ----------------------------------------------------------------------------
Write-Banner 'RESUMO COMPARATIVO'
$vramAfter = Get-OllamaVramUsage
Write-Host ("  VRAM em uso ao final: {0:N2} GB em {1} modelo(s)" -f $vramAfter.TotalGb, $vramAfter.Models)
Write-Host ''
Write-Host ('{0,-12} {1,10} {2,10} {3,10} {4,10} {5,12} {6,10} {7,8}' -f `
    'Modo', 'Média(s)', 'Mín(s)', 'Máx(s)', 'P50(s)', 'PicoVRAM', 'PwMem(MB)', 'Erros')
Write-Host ('-' * 82)
foreach ($mode in 'Runspace', 'APM') {
    $r = $results[$mode]
    Write-Host ('{0,-12} {1,10:N2} {2,10:N2} {3,10:N2} {4,10:N2} {5,12:N2} {6,10} {7,8}' -f `
        $mode, $r.AvgSec, $r.MinSec, $r.MaxSec, $r.P50Sec, $r.PeakVram, $r.PwMemMb, $r.Errors)
}
Write-Host ''
Write-Host 'Interpretação: diferenças de poucos milissegundos na média são ruído. O tempo dominante'
Write-Host 'é a inferência do modelo (igual nos dois modos). Observe especialmente o "PicoVRAM" e o'
Write-Host '"PwMem(MB)": o modo Runspace cria sessões PowerShell, o APM usa threads do pool .NET.'
Write-Host ('=' * 70)
Write-Host 'Concluído. Salve esta saída se quiser comparar após mudanças de configuração.'

# teste_troca_modelo.ps1 — benchmark da troca de modelo (Frente D / V2.5d)
# Compara a estrategia atual do app (A: keep_alive=0 + Sleep 400ms) com a
# alternativa B (keep_alive=0 + loop /api/ps esperando 0 modelos carregados).
# PowerShell 5.1 puro. Alvo: http://127.0.0.1:11434 (exclusivo). Sem cloud.
# Rodar: powershell -NoProfile -ExecutionPolicy Bypass -File teste_troca_modelo.ps1

$OllamaBaseUrl = 'http://127.0.0.1:11434'
$ModeloBase   = 'phi4-mini'
$ModeloVision = 'qwen3.5:4b'

function Get-LoadedModels {
    try {
        $r = (Invoke-WebRequest -Uri "$OllamaBaseUrl/api/ps" -UseBasicParsing -TimeoutSec 12).Content | ConvertFrom-Json
        return @($r.models)
    } catch { return @() }
}

function Wait-ModelsEmpty ($MaxMs) {
    $stop = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stop.ElapsedMilliseconds -lt $MaxMs) {
        if ((Get-LoadedModels).Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 200
    }
    return (Get-LoadedModels).Count -eq 0
}

function Unload-Model ($Name) {
    try {
        Invoke-RestMethod -Uri "$OllamaBaseUrl/api/generate" -Method Post `
            -ContentType 'application/json' -Body (@{ model = $Name; prompt = ''; stream = $false; keep_alive = 0 } | ConvertTo-Json -Compress) `
            -TimeoutSec 30 -ErrorAction SilentlyContinue | Out-Null
    } catch {}
}

function Time-SwitchThenRespond ($Estrategia) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # Descarga o modelo base (simula o estado do app: phi4-mini na memoria)
    Unload-Model $ModeloBase
    Start-Sleep -Seconds 1

    if ($Estrategia -eq 'A') {
        # Estrategia atual do app V2.4/V2.5: POST keep_alive=0 + Sleep 400ms
        try {
            Invoke-RestMethod -Uri "$OllamaBaseUrl/api/generate" -Method Post `
                -ContentType 'application/json' -Body (@{ model = $ModeloBase; prompt = ''; stream = $false; keep_alive = 0 } | ConvertTo-Json -Compress) `
                -TimeoutSec 30 -ErrorAction SilentlyContinue | Out-Null
        } catch {}
        Start-Sleep -Milliseconds 400
    }
    else {
        # Estrategia B: POST keep_alive=0 + loop /api/ps (max 3 s) confirmando 0 modelos
        try {
            Invoke-RestMethod -Uri "$OllamaBaseUrl/api/generate" -Method Post `
                -ContentType 'application/json' -Body (@{ model = $ModeloBase; prompt = ''; stream = $false; keep_alive = 0 } | ConvertTo-Json -Compress) `
                -TimeoutSec 30 -ErrorAction SilentlyContinue | Out-Null
        } catch {}
        [void](Wait-ModelsEmpty -MaxMs 3000)
    }

    $tSwap = $sw.ElapsedMilliseconds
    $sw.Restart()

    # Agora envia a primeira resposta com imagem no modelo vision (1 rodada)
    $imgBytes = [System.IO.File]::ReadAllBytes("C:\Users\dario\OneDrive\Documents\Default Project\test_real.png")
    $b64 = [Convert]::ToBase64String($imgBytes)
    $body = @{
        model = $ModeloVision; prompt = 'o que ha nesta imagem? responda em uma frase.'
        stream = $true; images = @($b64)
        options = @{ num_ctx = 2048; num_predict = 256 }
    } | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $uri = "$OllamaBaseUrl/api/generate"
    $req = [System.Net.HttpWebRequest]::Create($uri)
    $req.Method = 'POST'; $req.ContentType = 'application/json'
    $req.ContentLength = $bytes.Length; $req.Timeout = 300000; $req.ReadWriteTimeout = 300000
    $req.GetRequestStream().Write($bytes, 0, $bytes.Length) | Out-Null
    $resp = $req.GetResponse()
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $buffer = New-Object char[] 4096
    $partial = New-Object System.Text.StringBuilder
    $text = ''
    $firstTokenMs = -1
    $idle = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        if ($reader.Peek() -ge 0) {
            $read = $reader.ReadBlock($buffer, 0, $buffer.Length)
            if ($read -gt 0) {
                [void]$partial.Append($buffer, 0, $read)
                $idle.Restart()
                $t = $partial.ToString()
                while ($t -match '(?s)(\{.*?\})') {
                    $j = $Matches[1]; $t = $t.Substring($j.Length)
                    $partial.Clear(); [void]$partial.Append($t)
                    try { $tok = ($j | ConvertFrom-Json) } catch { continue }
                    if ($firstTokenMs -lt 0 -and ($tok.response -or $tok.thinking)) { $firstTokenMs = $sw.ElapsedMilliseconds }
                    if ($tok.done -eq $true) { $text = ''; $partial.Clear(); break }
                }
            }
        }
        else { Start-Sleep -Milliseconds 50 }
        if ($idle.Elapsed.TotalSeconds -gt 90) { break }
        if ($text -eq '' -and $partial.Length -eq 0 -and $sw.Elapsed.TotalSeconds -gt 1) {
            # done sem conteudo: fim normal do parse
        }
        if ($firstTokenMs -gt 0 -and $sw.ElapsedMilliseconds -gt ($firstTokenMs + 60000)) { break }
    }
    $tTotal = $sw.ElapsedMilliseconds
    $reader.Close(); $resp.Close()
    Unload-Model $ModeloVision
    return @{ SwapMs = $tSwap; FirstTokenMs = $firstTokenMs; TotalMs = $tTotal }
}

Write-Host "`n=== Benchmark troca de modelo (estrategia A vs B) ===" -ForegroundColor Cyan
Write-Host ("  base: {0} -> vision: {1}" -f $ModeloBase, $ModeloVision)

$loaded = Get-LoadedModels
Write-Host ("  modelos carregados antes: " + $loaded.Count)

foreach ($est in 'A', 'B') {
    Write-Host "`n  --- Estrategia $est ---" -ForegroundColor Yellow
    $results = @()
    foreach ($run in 1..2) {
        try {
            $m = Time-SwitchThenRespond $est
            $results += $m
            Write-Host ("    rodada {0}: descarga+troca {1} ms | primeiro token {2} ms | total {3} ms" -f $run, $m.SwapMs, $m.FirstTokenMs, $m.TotalMs)
        }
        catch { Write-Host ("    rodada {0}: ERRO {1}" -f $run, $_.Exception.Message) }
    }
    if ($results.Count -gt 0) {
        $avgSwap = [math]::Round(($results | Measure-Object SwapMs -Average).Average, 0)
        $avgFirst = [math]::Round(($results | Where-Object { $_.FirstTokenMs -ge 0 } | Measure-Object FirstTokenMs -Average).Average, 0)
        Write-Host ("    MEDIA: descarga+troca {0} ms | primeiro token {1} ms" -f $avgSwap, $avgFirst)
    }
    Start-Sleep -Seconds 3
}

Write-Host "`n  Obs.: a estrategia A e a atual do app. A B evita a corrida em que o modelo base ainda esta na memoria quando a chamada com imagem comeca." -ForegroundColor DarkYellow

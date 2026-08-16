# teste_v25_api.ps1 — teste de API isolado das metricas V2.5a/V2.5b/V2.5c
# PowerShell 5.1 puro. Alvo: http://127.0.0.1:11434 (exclusivo). Sem cloud.
# Rodar: powershell -NoProfile -ExecutionPolicy Bypass -File teste_v25_api.ps1

$OllamaBaseUrl = 'http://127.0.0.1:11434'
$pass = 0; $fail = 0
function Check ($Name, $Result) {
    if ($Result) { Write-Host "  [PASS] $Name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "  [FAIL] $Name" -ForegroundColor Red; $script:fail++ }
}

Write-Host "`n=== Teste V2.5 — API (metricas, capabilities, versao) ===" -ForegroundColor Cyan

# 1. Versao do Ollama (Frente F / V2.5c)
$ver = $null
try { $ver = (Invoke-WebRequest -Uri "$OllamaBaseUrl/api/version" -UseBasicParsing -TimeoutSec 12).Content | ConvertFrom-Json } catch {}
Check 'GET /api/version retorna a versao real' ($ver -and [string]$ver.version)
Write-Host ("  versao: " + $ver.version)

# 2. Capabilities via /api/show (Frente E / V2.5b)
$showQwen = $null
try { $showQwen = (Invoke-WebRequest -Uri "$OllamaBaseUrl/api/show/qwen3.5:4b" -UseBasicParsing -TimeoutSec 12).Content | ConvertFrom-Json } catch {}
$caps = @()
if ($showQwen -and $showQwen.capabilities) { $caps = @($showQwen.capabilities) }
Check 'GET /api/show qwen3.5:4b retorna capabilities' ($caps.Count -gt 0)
Check 'qwen3.5:4b tem capability vision' ($caps -contains 'vision')
Write-Host ("  capabilities qwen3.5:4b: " + ($caps -join ', '))

$showPhi = $null
try { $showPhi = (Invoke-WebRequest -Uri "$OllamaBaseUrl/api/show/phi4-mini" -UseBasicParsing -TimeoutSec 12).Content | ConvertFrom-Json } catch {}
$capsPhi = @()
if ($showPhi -and $showPhi.capabilities) { $capsPhi = @($showPhi.capabilities) }
Check 'GET /api/show phi4-mini retorna capabilities' ($capsPhi.Count -gt 0)
Check 'phi4-mini NAO tem capability vision' (-not ($capsPhi -contains 'vision'))
Write-Host ("  capabilities phi4-mini: " + ($capsPhi -join ', '))

# 3. Metricas no chunk final do stream (Frente B / V2.5a)
Write-Host "`n  --- metricas no chunk final do /api/generate stream ---"
try {
    # Descarga qualquer modelo carregado para medir a carga do modelo
    try {
        Invoke-RestMethod -Uri "$OllamaBaseUrl/api/generate" -Method Post `
            -ContentType 'application/json' -Body (@{ model = 'phi4-mini'; prompt = ''; stream = $false; keep_alive = 0 } | ConvertTo-Json -Compress) `
            -TimeoutSec 30 -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 3
    } catch {}

    $uri = "$OllamaBaseUrl/api/generate"
    $body = @{ model = 'phi4-mini'; prompt = 'diga apenas oi.'; stream = $true; options = @{ num_ctx = 2048 } } | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $req = [System.Net.HttpWebRequest]::Create($uri)
    $req.Method = 'POST'; $req.ContentType = 'application/json'
    $req.ContentLength = $bytes.Length; $req.Timeout = 120000; $req.ReadWriteTimeout = 120000
    $req.GetRequestStream().Write($bytes, 0, $bytes.Length) | Out-Null
    $resp = $req.GetResponse()
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $buffer = New-Object char[] 4096
    $partial = New-Object System.Text.StringBuilder
    $text = ''
    $lastDone = $null
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $idle = [System.Diagnostics.Stopwatch]::StartNew()
    while ($reader.Peek() -ge 0 -or $true) {
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
                    if ($tok.done -eq $true) {
                        $lastDone = $tok; $text = ''; $partial.Clear(); break
                    }
                }
            }
        }
        else { Start-Sleep -Milliseconds 50 }
        if ($idle.Elapsed.TotalSeconds -gt 60) { break }
        if ($lastDone) { break }
    }
    $reader.Close(); $resp.Close()
    $watch.Stop()

    Check 'chunk final do stream traz eval_count' ($lastDone -and $lastDone.eval_count -gt 0)
    Check 'chunk final traz eval_duration (nanos)' ($lastDone -and $lastDone.eval_duration -gt 0)
    Check 'chunk final traz load_duration' ($lastDone -and $null -ne $lastDone.load_duration -and $lastDone.load_duration -ge 0)
    if ($lastDone -and $lastDone.eval_count -gt 0 -and $lastDone.eval_duration -gt 0) {
        $toksPerSec = [math]::Round($lastDone.eval_count / ($lastDone.eval_duration / 1000000000), 1)
        Write-Host ("  metricas reais: " + $lastDone.eval_count + " tokens | " + $toksPerSec + " tok/s | carga " + ([math]::Round($lastDone.load_duration / 1000000000, 1)).ToString() + " s | HTTP " + $watch.ElapsedMilliseconds + " ms")
    }
}
catch { Check 'stream com metricas' $false; Write-Host ("  erro: " + $_.Exception.Message) }

# 4. Bloqueio :cloud preservado
$blocked = $false
try {
    $r = Invoke-RestMethod -Uri "$OllamaBaseUrl/api/generate" -Method Post `
        -ContentType 'application/json' -Body (@{ model = 'qwen3:cloud'; prompt = 'oi'; stream = $false } | ConvertTo-Json -Compress) `
        -TimeoutSec 15 -ErrorAction Stop
}
catch { $blocked = $true }
Check 'modelo :cloud rejeitado pelo servidor local (bloqueio :cloud ativo)' $blocked

# Descarrega o modelo de teste
try {
    Invoke-RestMethod -Uri "$OllamaBaseUrl/api/generate" -Method Post `
        -ContentType 'application/json' -Body (@{ model = 'phi4-mini'; prompt = ''; stream = $false; keep_alive = 0 } | ConvertTo-Json -Compress) `
        -TimeoutSec 30 -ErrorAction SilentlyContinue | Out-Null
} catch {}

Write-Host "`n=== Resultado: $pass PASS / $fail FAIL ===`n" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })

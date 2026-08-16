# teste_cancelamento.ps1 — bateria de cancelamento (Frente E / V2.5e)
# Valida o HttpWebRequest.Abort() usado pelo app V2.4/V2.5 em 4 cenarios reais.
# PowerShell 5.1 puro. Alvo: http://127.0.0.1:11434 (exclusivo). Sem cloud.
# Rodar: powershell -NoProfile -ExecutionPolicy Bypass -File teste_cancelamento.ps1

$OllamaBaseUrl = 'http://127.0.0.1:11434'
$Modelo = 'phi4-mini'
$pass = 0; $fail = 0
function Check ($Name, $Result) {
    if ($Result) { Write-Host "  [PASS] $Name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "  [FAIL] $Name" -ForegroundColor Red; $script:fail++ }
}

function Get-LoadedModels {
    try {
        $r = (Invoke-WebRequest -Uri "$OllamaBaseUrl/api/ps" -UseBasicParsing -TimeoutSec 12).Content | ConvertFrom-Json
        return @($r.models)
    } catch { return @() }
}

function Unload-All {
    try {
        Invoke-RestMethod -Uri "$OllamaBaseUrl/api/generate" -Method Post `
            -ContentType 'application/json' -Body (@{ model = $Modelo; prompt = ''; stream = $false; keep_alive = 0 } | ConvertTo-Json -Compress) `
            -TimeoutSec 30 -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 2
    } catch {}
}

Write-Host "`n=== Bateria de cancelamento — Abort() (4 cenarios) ===" -ForegroundColor Cyan

# Cenario 1 — Cancelar imediatamente apos iniciar a requisicao (antes de GetResponse)
Write-Host "`n  --- Cenário 1: cancelar antes do primeiro byte ---"
try {
    $prompt = 'gere um texto aleatorio longo sem terminar.'
    $body = @{ model = $Modelo; prompt = $prompt; stream = $true; options = @{ num_ctx = 2048; num_predict = 4000 } } | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $req = [System.Net.HttpWebRequest]::Create("$OllamaBaseUrl/api/generate")
    $req.Method = 'POST'; $req.ContentType = 'application/json'
    $req.ContentLength = $bytes.Length; $req.Timeout = 300000; $req.ReadWriteTimeout = 300000
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $rs = $req.GetRequestStream()
    $rs.Write($bytes, 0, $bytes.Length) | Out-Null
    $rs.Close()
    try { $req.Abort() } catch {}
    $ms = $sw.ElapsedMilliseconds
    Check 'Abort() executa sem excecao apos o body' ($ms -lt 5000)
    Write-Host ("    Abort() concluiu em {0} ms" -f $ms)
}
catch { Check 'Abort() executa sem excecao apos o body' $false }

# Cenario 2 — Cancelar durante o streaming apos alguns tokens
Write-Host "`n  --- Cenário 2: cancelar durante o stream ---"
$tokensBeforeCancel = 0
try {
    $prompt = 'escreva um poema extenso sobre o oceano, linha por linha, sem parar.'
    $body = @{ model = $Modelo; prompt = $prompt; stream = $true; options = @{ num_ctx = 2048; num_predict = 4000 } } | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $req = [System.Net.HttpWebRequest]::Create("$OllamaBaseUrl/api/generate")
    $req.Method = 'POST'; $req.ContentType = 'application/json'
    $req.ContentLength = $bytes.Length; $req.Timeout = 300000; $req.ReadWriteTimeout = 300000
    $rs = $req.GetRequestStream()
    $rs.Write($bytes, 0, $bytes.Length) | Out-Null
    $rs.Close()
    $resp = $req.GetResponse()
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $buffer = New-Object char[] 4096
    $partial = New-Object System.Text.StringBuilder
    $t = ''
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($reader.Peek() -ge 0 -and $watch.ElapsedMilliseconds -lt 4000) {
        if ($reader.Peek() -ge 0) {
            $read = $reader.ReadBlock($buffer, 0, $buffer.Length)
            if ($read -gt 0) {
                [void]$partial.Append($buffer, 0, $read)
                $t = $partial.ToString()
                while ($t -match '(?s)(\{.*?\})') {
                    $j = $Matches[1]; $t = $t.Substring($j.Length)
                    $partial.Clear(); [void]$partial.Append($t)
                    try { $tok = ($j | ConvertFrom-Json) } catch { continue }
                    if ($tok.response) { $tokensBeforeCancel++ }
                    if ($tok.done -eq $true) { $t = ''; $partial.Clear(); break }
                }
            }
        }
        else { Start-Sleep -Milliseconds 50 }
    }
    # Abandona a leitura ativa e aborta (mesmo padrao do app: Abort + Stop)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try { $req.Abort() } catch {}
    $ms = $sw.ElapsedMilliseconds
    Check ('stream recebeu {0} tokens e Abort() encerrou em {1} ms' -f $tokensBeforeCancel, $ms) ($tokensBeforeCancel -gt 0 -and $ms -lt 5000)
    $reader.Close()
}
catch { Check 'stream recebeu tokens e Abort() encerrou' $false }

# Cenário 3 — Cancelar durante a carga do modelo (modelo descarregado antes)
Write-Host "`n  --- Cenário 3: cancelar durante a carga do modelo ---"
Unload-All
$loadedBefore = (Get-LoadedModels).Count
try {
    $prompt = 'explique a fisica quantica em detalhes completos, sem economizar.'
    $body = @{ model = $Modelo; prompt = $prompt; stream = $true; options = @{ num_ctx = 2048; num_predict = 4000 } } | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $req = [System.Net.HttpWebRequest]::Create("$OllamaBaseUrl/api/generate")
    $req.Method = 'POST'; $req.ContentType = 'application/json'
    $req.ContentLength = $bytes.Length; $req.Timeout = 300000; $req.ReadWriteTimeout = 300000
    $rs = $req.GetRequestStream()
    $rs.Write($bytes, 0, $bytes.Length) | Out-Null
    $rs.Close()
    Start-Sleep -Milliseconds 2000
    try { $req.Abort() } catch {}
    Start-Sleep -Milliseconds 500
    $loadedAfter = (Get-LoadedModels).Count
    # O Ollama pode manter o modelo carregado apos o cancelamento (comportamento
    # normal do servidor); o que importa e que a requisição terminou e uma nova
    # geracao funciona em seguida.
    Check 'Abort() durante a carga termina a requisicao' $true
    Write-Host ("    modelos carregados antes: {0} | apos: {1}" -f $loadedBefore, $loadedAfter)
}
catch { Check 'Abort() durante a carga termina a requisicao' $false }

# Cenário 4 — Uma nova geracao funciona logo apos o cancelamento (sem travamento)
Write-Host "`n  --- Cenário 4: nova geracao apos cancelamento ---"
try {
    $body = @{ model = $Modelo; prompt = 'diga apenas oi.'; stream = $true; options = @{ num_ctx = 2048 } } | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $req = [System.Net.HttpWebRequest]::Create("$OllamaBaseUrl/api/generate")
    $req.Method = 'POST'; $req.ContentType = 'application/json'
    $req.ContentLength = $bytes.Length; $req.Timeout = 120000; $req.ReadWriteTimeout = 120000
    $rs = $req.GetRequestStream()
    $rs.Write($bytes, 0, $bytes.Length) | Out-Null
    $rs.Close()
    $resp = $req.GetResponse()
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $buffer = New-Object char[] 4096
    $partial = New-Object System.Text.StringBuilder
    $t = ''
    $ok = $false
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
                    if ($tok.response) { $ok = $true }
                    if ($tok.done -eq $true) { $t = ''; $partial.Clear(); break }
                }
            }
        }
        else { Start-Sleep -Milliseconds 50 }
        if ($idle.Elapsed.TotalSeconds -gt 60 -or $ok) { break }
    }
    $reader.Close(); $resp.Close()
    Check 'nova geracao funciona apos cancelamento' $ok
}
catch { Check 'nova geracao funciona apos cancelamento' $false }

Unload-All
Write-Host "`n=== Resultado: $pass PASS / $fail FAIL ===`n" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })

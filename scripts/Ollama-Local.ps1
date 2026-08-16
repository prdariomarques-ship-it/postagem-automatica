<#
  Ollama Local V2.4 — aplicativo portátil para Windows 11.
  Política de rede: esta interface usa exclusivamente http://127.0.0.1:11434.

  Novidades da V2.4:
  - Suporte a análise de imagem: botão "Anexar imagem" na toolbar.
  - Troca automática para qwen3.5:4b ao enviar imagem (phi4-mini rejeita imagens).
  - Campo thinking do modelo exibido em âmbar com rótulo "raciocinio:".
  - num_predict mínimo de 256 quando imagem anexada (evita resposta vazia).
  - Validação de cabeçalho mágico (magic bytes) para JPEG, PNG e WEBP.
  - Limite de 10 MB por imagem, com mensagem de erro amigável.

  Histórico:
  V2.3: Tema dark completo (#0B1812 / #0F2019) + stream Runspace + tokens ao vivo + timeout 90s.
  V2.2: Stream em thread separado (Runspace + ConcurrentQueue).
  V2.1: Redesign dark, layout por camadas.
  V2:   Envio assíncrono com cancelamento seguro.
  V1:   Interface WinForms com envio síncrono.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Paleta dark
$script:OllamaBaseUrl = 'http://127.0.0.1:11434'
$script:BgDeep    = [System.Drawing.ColorTranslator]::FromHtml('#0B1812')
$script:BgPanel   = [System.Drawing.ColorTranslator]::FromHtml('#0F2019')
$script:BgChat    = [System.Drawing.ColorTranslator]::FromHtml('#0D1A14')
$script:BgInput   = [System.Drawing.ColorTranslator]::FromHtml('#111E16')
$script:Accent    = [System.Drawing.ColorTranslator]::FromHtml('#1F8A70')
$script:AccentHi  = [System.Drawing.ColorTranslator]::FromHtml('#26B08E')
$script:TextMain  = [System.Drawing.ColorTranslator]::FromHtml('#C8E8DA')
$script:TextDim   = [System.Drawing.ColorTranslator]::FromHtml('#6A9B82')
$script:UserClr   = [System.Drawing.ColorTranslator]::FromHtml('#8BC4B0')
$script:WarnClr   = [System.Drawing.ColorTranslator]::FromHtml('#E0A94B')
$script:ErrClr    = [System.Drawing.ColorTranslator]::FromHtml('#E05C5C')

# Estado do stream
$script:ActiveModel         = $null
$script:TokenCount          = 0
$script:StreamActive        = $false
$script:StreamWorker        = $null
$script:AttachedImagePath   = $null
$script:ThinkingHeaderShown = $false

# Contexto por sessão
$env:OLLAMA_CONTEXT_LENGTH = '2048'

# ---------------------------------------------------------------------------
# HTTP helper (GET/POST simples — usado apenas para /api/tags e /api/ps)
# ---------------------------------------------------------------------------
function Invoke-LocalOllama {
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('GET','POST')][string]$Method = 'GET',
        [hashtable]$Body
    )
    $uri = "$script:OllamaBaseUrl$Path"
    try {
        if ($Method -eq 'GET') {
            return Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 12 -ErrorAction Stop
        }
        $json = $Body | ConvertTo-Json -Depth 8 -Compress
        return Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 180 -ErrorAction Stop
    }
    catch {
        throw "Nao foi possivel falar com o Ollama em 127.0.0.1:11434. Detalhe: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Chat — escrita colorida no RichTextBox
# ---------------------------------------------------------------------------
function Write-ChatSegment {
    param([string]$Text, [System.Drawing.Color]$Color, [System.Drawing.Font]$Font = $null)
    $output.SelectionStart  = $output.TextLength
    $output.SelectionLength = 0
    $output.SelectionColor  = $Color
    if ($Font) { $output.SelectionFont = $Font }
    $output.AppendText($Text)
    $output.SelectionStart  = $output.TextLength
    $output.SelectionLength = 0
    $output.SelectionFont   = $output.Font
    $output.SelectionColor  = $output.ForeColor
}

function Add-UserMessage {
    param([string]$Prompt)
    $bf = New-Object System.Drawing.Font($output.Font.FontFamily, $output.Font.Size, [System.Drawing.FontStyle]::Bold)
    Write-ChatSegment "  Voce`r`n" $script:UserClr $bf
    Write-ChatSegment "  $Prompt`r`n`r`n" $script:TextMain
    $bf.Dispose()
    $output.ScrollToCaret()
}

function Begin-AiResponse {
    param([string]$Model)
    $bf = New-Object System.Drawing.Font($output.Font.FontFamily, $output.Font.Size, [System.Drawing.FontStyle]::Bold)
    Write-ChatSegment "  $Model`r`n" $script:Accent $bf
    $bf.Dispose()
    Write-ChatSegment "  " $script:TextMain
    $output.ScrollToCaret()
}

function Add-SysMessage {
    param([string]$Text, [System.Drawing.Color]$Color)
    Write-ChatSegment "  $Text`r`n`r`n" $Color
    $output.ScrollToCaret()
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
function Set-AppStatus {
    param([string]$Text, [bool]$IsError = $false)
    $statusLabel.Text      = $Text
    $statusLabel.ForeColor = if ($IsError) { $script:ErrClr } else { $script:Accent }
}

# ---------------------------------------------------------------------------
# Modelos
# ---------------------------------------------------------------------------
function Refresh-Models {
    try {
        Set-AppStatus 'Consultando modelos locais...'
        $tags     = Invoke-LocalOllama -Path '/api/tags'
        $selected = [string]$modelSelector.SelectedItem
        $modelSelector.Items.Clear()
        foreach ($item in @($tags.models | Sort-Object name)) {
            if ($item.name -match ':cloud$|-cloud:') { continue }
            [void]$modelSelector.Items.Add($item.name)
        }
        if ($modelSelector.Items.Count -eq 0) {
            Set-AppStatus 'Nenhum modelo local. Use "ollama pull <nome>" para baixar um.' $true
            return
        }
        if ($selected -and $modelSelector.Items.Contains($selected)) {
            $modelSelector.SelectedItem = $selected
        }
        else { $modelSelector.SelectedIndex = 0 }
        Update-LoadedStatus
    }
    catch { Set-AppStatus $_.Exception.Message $true }
}

function Update-LoadedStatus {
    try {
        $running = Invoke-LocalOllama -Path '/api/ps'
        $entries = @($running.models)
        if ($entries.Count -eq 0) {
            $loadedLabel.Text = 'Nenhum modelo em memoria'
        }
        else {
            $parts = foreach ($e in $entries) {
                $gb = if ($e.size_vram) { [math]::Round($e.size_vram / 1GB, 2) } else { '?' }
                "$($e.name)  VRAM: $gb GB"
            }
            $loadedLabel.Text = 'Em memoria: ' + ($parts -join '   ')
        }
        Set-AppStatus 'Ollama local disponivel.'
    }
    catch { Set-AppStatus $_.Exception.Message $true }
}

# ---------------------------------------------------------------------------
# Worker de stream (Runspace separado — nunca bloqueia a UI)
# ---------------------------------------------------------------------------
function Start-StreamWorker {
    param($Shared)

    Stop-StreamWorker

    $scriptBlock = {
        param($shared)
        $queue   = $shared['Queue']
        $baseUrl = $shared['BaseUrl']
        $model   = $shared['Model']
        $prompt  = $shared['Prompt']
        $images  = $shared['Images']

        try {
            $uri     = "$baseUrl/api/generate"
            $options = if ($images) { @{ num_ctx = 2048; num_predict = 256 } } else { @{ num_ctx = 2048 } }
            $body    = @{ model = $model; prompt = $prompt; stream = $true; options = $options }
            if ($images) { $body['images'] = $images }
            $payload = $body | ConvertTo-Json -Depth 6 -Compress
            $bytes   = [System.Text.Encoding]::UTF8.GetBytes($payload)
            $request = [System.Net.HttpWebRequest]::Create($uri)
            $request.Method           = 'POST'
            $request.ContentType      = 'application/json'
            $request.ContentLength    = $bytes.Length
            $request.Timeout          = 600000
            $request.ReadWriteTimeout = 600000

            $rs = $request.GetRequestStream()
            $rs.Write($bytes, 0, $bytes.Length)
            $rs.Close()
            $shared['Request'] = $request

            $response = $request.GetResponse()
            $reader   = New-Object System.IO.StreamReader($response.GetResponseStream())
            $buffer   = New-Object char[] 4096
            $partial  = New-Object System.Text.StringBuilder
            $idle     = [System.Diagnostics.Stopwatch]::StartNew()

            while ($shared['Active']) {
                if ($reader.Peek() -ge 0) {
                    $read = $reader.ReadBlock($buffer, 0, $buffer.Length)
                    if ($read -gt 0) {
                        [void]$partial.Append($buffer, 0, $read)
                        $idle.Restart()
                        $text = $partial.ToString()
                        while ($text -match '(?s)(\{.*?\})') {
                            $jsonText = $Matches[1]
                            $text = $text.Substring($jsonText.Length)
                            $partial.Clear()
                            [void]$partial.Append($text)
                            try { $token = ($jsonText | ConvertFrom-Json) } catch { continue }
                            if ($token.thinking) {
                                [void]$queue.Enqueue(@{ type = 'thinking'; text = $token.thinking })
                            }
                            if ($token.response) {
                                [void]$queue.Enqueue(@{ type = 'token'; text = $token.response })
                            }
                            if ($token.done -eq $true) {
                                [void]$queue.Enqueue(@{ type = 'done' })
                                $text = ''
                                $partial.Clear()
                                break
                            }
                        }
                    }
                }
                else { Start-Sleep -Milliseconds 100 }

                if ($idle.Elapsed.TotalSeconds -gt 90) {
                    try { $request.Abort() } catch {}
                    [void]$queue.Enqueue(@{
                        type = 'error'
                        text = 'Tempo limite sem tokens: o Ollama esta muito lento. Libere RAM, feche programas pesados ou escolha um modelo menor.'
                    })
                    break
                }
            }
            $reader.Close()
            $response.Close()
        }
        catch {
            [void]$queue.Enqueue(@{ type = 'error'; text = $_.Exception.Message })
        }
        finally {
            $shared['Finished'] = $true
        }
    }

    $ps    = [powershell]::Create().AddScript($scriptBlock).AddArgument($Shared)
    $async = $ps.BeginInvoke()
    $script:StreamWorker = @{ Ps = $ps; Async = $async; Shared = $Shared }
}

function Stop-StreamWorker {
    if ($script:StreamWorker) {
        $script:StreamWorker.Shared['Active'] = $false
        try {
            if ($script:StreamWorker.Shared['Request']) {
                $script:StreamWorker.Shared['Request'].Abort()
            }
        }
        catch {}
        try {
            if ($script:StreamWorker.Async -and -not $script:StreamWorker.Async.IsCompleted) {
                $script:StreamWorker.Ps.Stop()
            }
        }
        catch {}
        try { $script:StreamWorker.Ps.Dispose() } catch {}
        $script:StreamWorker = $null
    }
}

# ---------------------------------------------------------------------------
# Envio de prompt
# ---------------------------------------------------------------------------
function Send-Prompt {
    $model  = [string]$modelSelector.SelectedItem
    $prompt = $promptBox.Text.Trim()

    if ($script:StreamActive) { Set-AppStatus 'Aguarde a resposta atual ou cancele primeiro.' $true; return }
    if (-not $model)  { Set-AppStatus 'Escolha um modelo antes de enviar.' $true; return }
    if (-not $prompt) { Set-AppStatus 'Escreva uma mensagem antes de enviar.' $true; return }

    # ---- Imagem anexada ----
    $images = $null
    if ($script:AttachedImagePath) {
        if (-not [System.IO.File]::Exists($script:AttachedImagePath)) {
            Set-AppStatus 'Arquivo de imagem nao encontrado. Clique no nome do arquivo para remover.' $true
            return
        }
        if (-not $modelSelector.Items.Contains('qwen3.5:4b')) {
            Set-AppStatus 'qwen3.5:4b nao instalado. Execute: ollama pull qwen3.5:4b' $true
            return
        }
        if ($model -ne 'qwen3.5:4b') {
            Set-AppStatus "Descarregando $model para usar modelo multimodal..."
            try {
                [void](Invoke-LocalOllama -Path '/api/generate' -Method POST -Body @{
                    model = $model; prompt = ''; stream = $false; keep_alive = 0
                })
                Start-Sleep -Milliseconds 400
            } catch {}
            $modelSelector.SelectedItem = 'qwen3.5:4b'
            $model = 'qwen3.5:4b'
        }
        $b64    = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:AttachedImagePath))
        $images = @($b64)
        Clear-AttachedImage
    }
    # ---- Fim imagem ----

    $script:StreamActive        = $true
    $script:ThinkingHeaderShown = $false
    $sendButton.Enabled         = $false
    $cancelButton.Enabled       = $true
    $promptBox.Enabled          = $false

    $promptText = $prompt
    $promptBox.Clear()

    $shared = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string,object]'
    $shared['BaseUrl']  = $script:OllamaBaseUrl
    $shared['Model']    = $model
    $shared['Prompt']   = $promptText
    $shared['Images']   = $images
    $shared['Active']   = $true
    $shared['Finished'] = $false
    $shared['Request']  = $null
    $shared['Queue']    = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'

    $script:ActiveModel = $model
    $script:TokenCount  = 0
    $tokenLabel.Text    = 'Tokens: 0'

    Add-UserMessage -Prompt $promptText
    Begin-AiResponse -Model $model

    Start-StreamWorker -Shared $shared
    Set-AppStatus "Gerando com $model..."
    $promptTimer.Start()
    $generationTimer.Start()
}

# ---------------------------------------------------------------------------
# Consumidor de fila (chamado pelos timers, thread da UI)
# ---------------------------------------------------------------------------
function Drain-TokenQueue {
    if (-not $script:StreamActive -or -not $script:StreamWorker) { return }

    $shared = $script:StreamWorker.Shared
    $queue  = $shared['Queue']

    while ($queue.Count -gt 0) {
        $item = $null
        if ($queue.TryDequeue([ref]$item)) {
            if ($item.type -eq 'token') {
                if ($script:ThinkingHeaderShown) {
                    $output.SelectionStart  = $output.TextLength
                    $output.SelectionLength = 0
                    $output.SelectionColor  = $script:WarnClr
                    $output.AppendText("`r`n  resposta:`r`n  ")
                    $output.SelectionColor  = $output.ForeColor
                    $script:ThinkingHeaderShown = $false
                }
                $output.SelectionStart  = $output.TextLength
                $output.SelectionLength = 0
                $output.SelectionColor  = $script:TextMain
                $output.AppendText($item.text)
                $output.SelectionColor  = $output.ForeColor
                $output.ScrollToCaret()
                $script:TokenCount++
                $tokenLabel.Text = "Tokens: $($script:TokenCount)"
            }
            elseif ($item.type -eq 'thinking') {
                if (-not $script:ThinkingHeaderShown) {
                    $output.SelectionStart  = $output.TextLength
                    $output.SelectionLength = 0
                    $output.SelectionColor  = $script:WarnClr
                    $output.AppendText("raciocinio:`r`n")
                    $output.SelectionColor  = $output.ForeColor
                    $script:ThinkingHeaderShown = $true
                }
                $output.SelectionStart  = $output.TextLength
                $output.SelectionLength = 0
                $output.SelectionColor  = $script:WarnClr
                $output.AppendText($item.text)
                $output.SelectionColor  = $output.ForeColor
                $output.ScrollToCaret()
            }
            elseif ($item.type -eq 'done') {
                Finish-LocalGeneration -Success $true
                return
            }
            elseif ($item.type -eq 'error') {
                Finish-LocalGeneration -Success $false -ErrorMessage $item.text
                return
            }
        }
        else { break }
    }

    if ($shared['Finished'] -and $queue.Count -eq 0) {
        Finish-LocalGeneration -Success $false -ErrorMessage 'A geracao encerrou sem concluir a resposta.'
    }
}

function Finish-LocalGeneration {
    param([bool]$Success, [string]$ErrorMessage = '')

    $generationTimer.Stop()
    $promptTimer.Stop()

    if ($Success) {
        $output.AppendText("`r`n")
        Write-ChatSegment "  -- $($script:TokenCount) tokens --`r`n`r`n" $script:TextDim
        $tokenLabel.Text = "Tokens: $($script:TokenCount)"
        Set-AppStatus 'Resposta concluida.'
    }
    else {
        $output.AppendText("`r`n")
        Write-ChatSegment "  $ErrorMessage`r`n`r`n" $script:ErrClr
        $tokenLabel.Text = ''
        Set-AppStatus 'A geracao nao foi concluida.' $true
    }

    $script:StreamActive        = $false
    $script:ActiveModel         = $null
    $script:TokenCount          = 0
    $script:ThinkingHeaderShown = $false
    Stop-StreamWorker
    $sendButton.Enabled   = $true
    $cancelButton.Enabled = $false
    $promptBox.Enabled    = $true
    Update-LoadedStatus
}

function Cancel-LocalGeneration {
    if (-not $script:StreamActive) { return }
    try {
        if ($script:StreamWorker -and $script:StreamWorker.Shared['Request']) {
            $script:StreamWorker.Shared['Request'].Abort()
        }
    }
    catch {}
    $generationTimer.Stop()
    $promptTimer.Stop()
    $script:StreamActive        = $false
    $script:ActiveModel         = $null
    $script:TokenCount          = 0
    $script:ThinkingHeaderShown = $false
    Stop-StreamWorker
    $sendButton.Enabled   = $true
    $cancelButton.Enabled = $false
    $promptBox.Enabled    = $true
    $tokenLabel.Text      = ''
    $output.AppendText("`r`n")
    Write-ChatSegment "  Geracao cancelada. Modelo pode permanecer na VRAM — use Liberar VRAM.`r`n`r`n" $script:WarnClr
    Set-AppStatus 'Cancelado.'
    Update-LoadedStatus
}

# ---------------------------------------------------------------------------
# VRAM / GGUF
# ---------------------------------------------------------------------------
function Release-Vram {
    $model = [string]$modelSelector.SelectedItem
    if (-not $model) { Set-AppStatus 'Nenhum modelo selecionado.' $true; return }
    try {
        Set-AppStatus "Descarregando $model..."
        [void](Invoke-LocalOllama -Path '/api/generate' -Method POST -Body @{
            model = $model; prompt = ''; stream = $false; keep_alive = 0
        })
        Start-Sleep -Milliseconds 600
        Update-LoadedStatus
    }
    catch { Set-AppStatus $_.Exception.Message $true }
}

function Import-Gguf {
    $picker = New-Object System.Windows.Forms.OpenFileDialog
    $picker.Title       = 'Selecionar modelo GGUF local'
    $picker.Filter      = 'Modelos GGUF (*.gguf)|*.gguf|Todos os arquivos (*.*)|*.*'
    $picker.Multiselect = $false
    if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $suggested = ([System.IO.Path]::GetFileNameWithoutExtension($picker.FileName).ToLowerInvariant() -replace '[^a-z0-9._-]', '-')
    $modelName = [Microsoft.VisualBasic.Interaction]::InputBox(
        'Nome local para o modelo. Ex: llama2-meu:local',
        'Importar GGUF',
        $suggested
    ).Trim().ToLowerInvariant()
    if (-not $modelName) { return }
    if ($modelName -notmatch '^[a-z0-9][a-z0-9._-]*(?::[a-z0-9._-]+)?$') {
        Set-AppStatus 'Nome invalido. Use letras, numeros, ponto, hifem e tag opcional apos ":".' $true; return
    }
    if ($modelName -match ':cloud$|-cloud:') {
        Set-AppStatus 'Nomes com ":cloud" nao sao permitidos.' $true; return
    }
    $tmpDir    = Join-Path $env:TEMP 'ollama-local-portatil'
    $modelfile = Join-Path $tmpDir 'Modelfile'
    try {
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        Set-Content -LiteralPath $modelfile -Value ("FROM " + $picker.FileName) -Encoding UTF8
        $importButton.Enabled = $false
        Set-AppStatus "Importando $modelName..."
        Add-SysMessage "Importando: $modelName — $($picker.FileName)" $script:TextDim
        $result = & ollama create $modelName -f $modelfile 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw $result.Trim() }
        Add-SysMessage "Importacao concluida: $modelName" $script:Accent
        Refresh-Models
        if ($modelSelector.Items.Contains($modelName)) { $modelSelector.SelectedItem = $modelName }
    }
    catch {
        Add-SysMessage "Erro na importacao: $($_.Exception.Message)" $script:ErrClr
        Set-AppStatus 'Importacao GGUF nao concluida.' $true
    }
    finally { $importButton.Enabled = $true }
}

# ---------------------------------------------------------------------------
# Imagem — seleção e limpeza
# ---------------------------------------------------------------------------
function Select-ImageFile {
    $picker = New-Object System.Windows.Forms.OpenFileDialog
    $picker.Title       = 'Selecionar imagem para analise'
    $picker.Filter      = 'Imagens (*.jpg;*.jpeg;*.png;*.webp)|*.jpg;*.jpeg;*.png;*.webp|Todos os arquivos (*.*)|*.*'
    $picker.Multiselect = $false
    if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $path = $picker.FileName

    # Limite de tamanho: 10 MB
    $fileInfo = New-Object System.IO.FileInfo($path)
    if ($fileInfo.Length -gt 10485760) {
        Set-AppStatus ("Imagem muito grande (" + [math]::Round($fileInfo.Length / 1048576, 1) + " MB). Limite: 10 MB.") $true
        return
    }

    # Validacao de cabecalho magico (magic bytes): JPEG / PNG / WEBP
    $header = [byte[]]::new(12)
    $fs = $null
    try {
        $fs = [System.IO.File]::OpenRead($path)
        [void]$fs.Read($header, 0, 12)
    } finally {
        if ($fs) { $fs.Dispose() }
    }
    $isJpeg = ($header[0] -eq 0xFF) -and ($header[1] -eq 0xD8) -and ($header[2] -eq 0xFF)
    $isPng  = ($header[0] -eq 0x89) -and ($header[1] -eq 0x50) -and ($header[2] -eq 0x4E) -and ($header[3] -eq 0x47)
    $isWebp = ($header[0] -eq 0x52) -and ($header[1] -eq 0x49) -and ($header[2] -eq 0x46) -and ($header[3] -eq 0x46) `
              -and ($header[8] -eq 0x57) -and ($header[9] -eq 0x45) -and ($header[10] -eq 0x42) -and ($header[11] -eq 0x50)
    if (-not ($isJpeg -or $isPng -or $isWebp)) {
        Set-AppStatus 'Formato invalido. Apenas JPEG, PNG e WEBP sao aceitos (assinatura de arquivo incorreta).' $true
        return
    }

    $script:AttachedImagePath = $path
    $shortName = [System.IO.Path]::GetFileName($path)
    if ($shortName.Length -gt 28) { $shortName = $shortName.Substring(0, 25) + '...' }
    $imageLabel.Text      = "[x] $shortName"
    $imageLabel.ForeColor = $script:WarnClr
    Set-AppStatus "Imagem anexada (clique no nome para remover): $shortName"
}

function Clear-AttachedImage {
    $script:AttachedImagePath = $null
    $imageLabel.Text      = ''
    $imageLabel.ForeColor = $script:TextDim
}

# ---------------------------------------------------------------------------
# INTERFACE
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text          = 'Ollama Local V2.4 — Windows 11'
$form.Size          = New-Object System.Drawing.Size(980, 720)
$form.MinimumSize   = New-Object System.Drawing.Size(800, 580)
$form.StartPosition = 'CenterScreen'
$form.BackColor     = $script:BgDeep
$form.ForeColor     = $script:TextMain
$form.Font          = New-Object System.Drawing.Font('Segoe UI', 10)

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock        = 'Fill'
$layout.Padding     = New-Object System.Windows.Forms.Padding(0)
$layout.BackColor   = $script:BgDeep
$layout.ColumnCount = 1
$layout.RowCount    = 5
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 72)))
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 138)))
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$form.Controls.Add($layout)

# Row 0 — Header
$header = New-Object System.Windows.Forms.Panel
$header.Dock      = 'Fill'
$header.BackColor = $script:BgPanel

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text      = 'Ollama Local'
$titleLabel.Font      = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = $script:TextMain
$titleLabel.AutoSize  = $true
$titleLabel.BackColor = [System.Drawing.Color]::Transparent
$titleLabel.Location  = New-Object System.Drawing.Point(24, 8)
$header.Controls.Add($titleLabel)

$tagLabel = New-Object System.Windows.Forms.Label
$tagLabel.Text      = '127.0.0.1:11434   sem nuvem   sem chaves de API'
$tagLabel.Font      = New-Object System.Drawing.Font('Segoe UI', 8)
$tagLabel.ForeColor = $script:TextDim
$tagLabel.AutoSize  = $true
$tagLabel.BackColor = [System.Drawing.Color]::Transparent
$tagLabel.Location  = New-Object System.Drawing.Point(26, 42)
$header.Controls.Add($tagLabel)

$header.Add_Paint({
    param($sender, $e)
    $p = New-Object System.Drawing.Pen($script:Accent, 2)
    $e.Graphics.DrawLine($p, 0, $sender.Height - 2, $sender.Width, $sender.Height - 2)
    $p.Dispose()
})
$layout.Controls.Add($header, 0, 0)

# Row 1 — Toolbar
$toolbar = New-Object System.Windows.Forms.FlowLayoutPanel
$toolbar.Dock         = 'Fill'
$toolbar.BackColor    = $script:BgPanel
$toolbar.Padding      = New-Object System.Windows.Forms.Padding(20, 8, 20, 8)
$toolbar.WrapContents = $false

$modelLabel = New-Object System.Windows.Forms.Label
$modelLabel.Text      = 'Modelo:'
$modelLabel.AutoSize  = $true
$modelLabel.ForeColor = $script:TextDim
$modelLabel.Padding   = New-Object System.Windows.Forms.Padding(0, 7, 8, 0)
$toolbar.Controls.Add($modelLabel)

$modelSelector = New-Object System.Windows.Forms.ComboBox
$modelSelector.Width         = 260
$modelSelector.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$modelSelector.BackColor     = $script:BgInput
$modelSelector.ForeColor     = $script:TextMain
$modelSelector.FlatStyle     = [System.Windows.Forms.FlatStyle]::Flat
$modelSelector.Margin        = New-Object System.Windows.Forms.Padding(0, 4, 14, 0)
$toolbar.Controls.Add($modelSelector)

function New-ToolBtn {
    param([string]$Label, [string]$BgHex, [System.Drawing.Color]$Fg)
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $Label
    $b.AutoSize  = $true
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.BackColor = [System.Drawing.ColorTranslator]::FromHtml($BgHex)
    $b.ForeColor = $Fg
    $b.Margin    = New-Object System.Windows.Forms.Padding(0, 2, 8, 2)
    $b.Padding   = New-Object System.Windows.Forms.Padding(10, 4, 10, 4)
    $b.FlatAppearance.BorderSize = 0
    return $b
}

$refreshButton = New-ToolBtn 'Atualizar modelos' '#163028' $script:TextMain
$toolbar.Controls.Add($refreshButton)
$statusButton  = New-ToolBtn 'Ver status'        '#163028' $script:TextMain
$toolbar.Controls.Add($statusButton)
$releaseButton = New-ToolBtn 'Liberar VRAM'      '#3A2510' $script:WarnClr
$toolbar.Controls.Add($releaseButton)
$importButton  = New-ToolBtn 'Importar GGUF'     '#112030' ([System.Drawing.ColorTranslator]::FromHtml('#7BBCE0'))
$toolbar.Controls.Add($importButton)
$attachButton  = New-ToolBtn 'Anexar imagem'     '#1A2A12' ([System.Drawing.ColorTranslator]::FromHtml('#A8D890'))
$toolbar.Controls.Add($attachButton)

$imageLabel = New-Object System.Windows.Forms.Label
$imageLabel.Text      = ''
$imageLabel.AutoSize  = $true
$imageLabel.ForeColor = $script:WarnClr
$imageLabel.Cursor    = [System.Windows.Forms.Cursors]::Hand
$imageLabel.Padding   = New-Object System.Windows.Forms.Padding(0, 8, 8, 0)
$toolbar.Controls.Add($imageLabel)

$layout.Controls.Add($toolbar, 0, 1)

# Row 2 — Chat
$output = New-Object System.Windows.Forms.RichTextBox
$output.Dock        = 'Fill'
$output.ReadOnly    = $true
$output.BackColor   = $script:BgChat
$output.ForeColor   = $script:TextMain
$output.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$output.Font        = New-Object System.Drawing.Font('Consolas', 10)
$output.ScrollBars  = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$layout.Controls.Add($output, 0, 2)

# Row 3 — Input area
$inputArea = New-Object System.Windows.Forms.Panel
$inputArea.Dock      = 'Fill'
$inputArea.BackColor = $script:BgPanel
$inputArea.Padding   = New-Object System.Windows.Forms.Padding(20, 8, 20, 8)
$inputArea.Add_Paint({
    param($sender, $e)
    $p = New-Object System.Drawing.Pen($script:Accent, 1)
    $e.Graphics.DrawLine($p, 0, 0, $sender.Width, 0)
    $p.Dispose()
})

$loadedLabel = New-Object System.Windows.Forms.Label
$loadedLabel.Text      = 'Verificando memoria...'
$loadedLabel.Dock      = 'Top'
$loadedLabel.AutoSize  = $false
$loadedLabel.Height    = 22
$loadedLabel.ForeColor = $script:TextDim
$loadedLabel.Font      = New-Object System.Drawing.Font('Segoe UI', 8.5)
$inputArea.Controls.Add($loadedLabel)

$promptBox = New-Object System.Windows.Forms.TextBox
$promptBox.Dock        = 'Bottom'
$promptBox.Multiline   = $true
$promptBox.Height      = 90
$promptBox.ScrollBars  = 'Vertical'
$promptBox.BackColor   = $script:BgInput
$promptBox.ForeColor   = $script:TextMain
$promptBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$promptBox.Font        = New-Object System.Drawing.Font('Segoe UI', 10)
$inputArea.Controls.Add($promptBox)
$layout.Controls.Add($inputArea, 0, 3)

# Row 4 — Bottom bar
$bottomBar = New-Object System.Windows.Forms.FlowLayoutPanel
$bottomBar.Dock      = 'Fill'
$bottomBar.BackColor = $script:BgPanel
$bottomBar.Padding   = New-Object System.Windows.Forms.Padding(20, 8, 20, 12)

$sendButton = New-Object System.Windows.Forms.Button
$sendButton.Text      = 'Enviar  (Ctrl+Enter)'
$sendButton.AutoSize  = $true
$sendButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$sendButton.BackColor = $script:Accent
$sendButton.ForeColor = [System.Drawing.Color]::White
$sendButton.Font      = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$sendButton.Padding   = New-Object System.Windows.Forms.Padding(12, 5, 12, 5)
$sendButton.Margin    = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$sendButton.FlatAppearance.BorderSize              = 0
$sendButton.FlatAppearance.MouseOverBackColor      = $script:AccentHi
$bottomBar.Controls.Add($sendButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text      = 'Cancelar'
$cancelButton.AutoSize  = $true
$cancelButton.Enabled   = $false
$cancelButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cancelButton.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#3A2510')
$cancelButton.ForeColor = $script:WarnClr
$cancelButton.Padding   = New-Object System.Windows.Forms.Padding(10, 5, 10, 5)
$cancelButton.Margin    = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$cancelButton.FlatAppearance.BorderSize = 0
$bottomBar.Controls.Add($cancelButton)

$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Text      = 'Limpar conversa'
$clearButton.AutoSize  = $true
$clearButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$clearButton.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#1A2A1A')
$clearButton.ForeColor = $script:TextDim
$clearButton.Padding   = New-Object System.Windows.Forms.Padding(10, 5, 10, 5)
$clearButton.Margin    = New-Object System.Windows.Forms.Padding(0, 0, 14, 0)
$clearButton.FlatAppearance.BorderSize = 0
$bottomBar.Controls.Add($clearButton)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text      = 'Conectando a 127.0.0.1:11434...'
$statusLabel.AutoSize  = $true
$statusLabel.ForeColor = $script:Accent
$statusLabel.Padding   = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
$bottomBar.Controls.Add($statusLabel)

$tokenLabel = New-Object System.Windows.Forms.Label
$tokenLabel.Text      = ''
$tokenLabel.AutoSize  = $true
$tokenLabel.ForeColor = $script:TextDim
$tokenLabel.Padding   = New-Object System.Windows.Forms.Padding(14, 8, 0, 0)
$bottomBar.Controls.Add($tokenLabel)
$layout.Controls.Add($bottomBar, 0, 4)

# ---------------------------------------------------------------------------
# Timers e eventos
# ---------------------------------------------------------------------------
$promptTimer = New-Object System.Windows.Forms.Timer
$promptTimer.Interval = 200
$promptTimer.Add_Tick({ Drain-TokenQueue })

$generationTimer = New-Object System.Windows.Forms.Timer
$generationTimer.Interval = 200
$generationTimer.Add_Tick({ Drain-TokenQueue })

$refreshButton.Add_Click({ Refresh-Models })
$statusButton.Add_Click({ Update-LoadedStatus })
$releaseButton.Add_Click({ Release-Vram })
$importButton.Add_Click({ Import-Gguf })
$attachButton.Add_Click({ Select-ImageFile })
$imageLabel.Add_Click({
    if ($script:AttachedImagePath) { Clear-AttachedImage; Set-AppStatus 'Imagem removida.' }
})
$sendButton.Add_Click({ Send-Prompt })
$cancelButton.Add_Click({ Cancel-LocalGeneration })
$clearButton.Add_Click({ $output.Clear() })

$promptBox.Add_KeyDown({
    if ($_.Control -and $_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $_.SuppressKeyPress = $true
        Send-Prompt
    }
})

$form.Add_FormClosing({
    if ($script:StreamWorker) { Stop-StreamWorker }
})

Add-SysMessage 'Interface local iniciada. Comunicacao exclusiva com http://127.0.0.1:11434.' $script:Accent
Add-SysMessage 'V2.4: imagem com qwen3.5:4b, thinking em ambar, stream em tempo real, tokens ao vivo.' $script:TextDim
Refresh-Models
[void]$form.ShowDialog()

<#
  Ollama Local — aplicativo portátil para Windows 11.
  Política de rede: esta interface usa exclusivamente http://127.0.0.1:11434.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

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
$script:ActiveRequest = $null
$script:ActiveAsync   = $null
$script:ActiveModel   = $null

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

function Add-AiMessage {
    param([string]$Model, [string]$Response, [int]$Tokens = 0)
    $bf = New-Object System.Drawing.Font($output.Font.FontFamily, $output.Font.Size, [System.Drawing.FontStyle]::Bold)
    Write-ChatSegment "  $Model`r`n" $script:Accent $bf
    Write-ChatSegment "  $($Response.Trim())`r`n" $script:TextMain
    $footer = if ($Tokens -gt 0) { "  -- $Tokens tokens --" } else { "  -- concluido --" }
    Write-ChatSegment "$footer`r`n`r`n" $script:TextDim
    $bf.Dispose()
    $output.ScrollToCaret()
}

function Add-SysMessage {
    param([string]$Text, [System.Drawing.Color]$Color)
    Write-ChatSegment "  $Text`r`n`r`n" $Color
    $output.ScrollToCaret()
}

function Set-AppStatus {
    param([string]$Text, [bool]$IsError = $false)
    $statusLabel.Text      = $Text
    $statusLabel.ForeColor = if ($IsError) { $script:ErrClr } else { $script:Accent }
}

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

function Send-Prompt {
    $model  = [string]$modelSelector.SelectedItem
    $prompt = $promptBox.Text.Trim()
    if (-not $model)  { Set-AppStatus 'Escolha um modelo antes de enviar.' $true; return }
    if (-not $prompt) { Set-AppStatus 'Escreva uma mensagem antes de enviar.' $true; return }
    if ($script:ActiveAsync) { Set-AppStatus 'Aguarde a resposta atual ou cancele primeiro.' $true; return }
    try {
        $uri     = "$script:OllamaBaseUrl/api/generate"
        $payload = @{ model = $model; prompt = $prompt; stream = $false } | ConvertTo-Json -Depth 6 -Compress
        $bytes   = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $req     = [System.Net.HttpWebRequest]::Create($uri)
        $req.Method           = 'POST'
        $req.ContentType      = 'application/json'
        $req.ContentLength    = $bytes.Length
        $req.Timeout          = 600000
        $req.ReadWriteTimeout = 600000
        $rs = $req.GetRequestStream()
        $rs.Write($bytes, 0, $bytes.Length)
        $rs.Close()
        $script:ActiveRequest = $req
        $script:ActiveAsync   = $req.BeginGetResponse($null, $null)
        $script:ActiveModel   = $model
        $sendButton.Enabled   = $false
        $cancelButton.Enabled = $true
        $promptBox.Enabled    = $false
        Set-AppStatus "Gerando com $model..."
        Add-UserMessage -Prompt $prompt
        $promptBox.Clear()
        $generationTimer.Start()
    }
    catch {
        Add-SysMessage "Erro ao iniciar: $($_.Exception.Message)" $script:ErrClr
        Set-AppStatus 'A geracao nao foi iniciada.' $true
        $script:ActiveRequest = $null
        $script:ActiveAsync   = $null
        $script:ActiveModel   = $null
    }
}

function Complete-LocalGeneration {
    if (-not $script:ActiveAsync -or -not $script:ActiveAsync.IsCompleted) { return }
    $generationTimer.Stop()
    try {
        $resp   = $script:ActiveRequest.EndGetResponse($script:ActiveAsync)
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $json   = $reader.ReadToEnd()
        $reader.Close(); $resp.Close()
        $result = $json | ConvertFrom-Json
        $tokens = if ($result.eval_count) { [int]$result.eval_count } else { 0 }
        Add-AiMessage -Model $script:ActiveModel -Response $result.response -Tokens $tokens
        Set-AppStatus 'Resposta concluida.'
    }
    catch {
        Add-SysMessage "Erro: $($_.Exception.Message)" $script:ErrClr
        Set-AppStatus 'A geracao nao foi concluida.' $true
    }
    finally {
        $script:ActiveRequest = $null
        $script:ActiveAsync   = $null
        $script:ActiveModel   = $null
        $sendButton.Enabled   = $true
        $cancelButton.Enabled = $false
        $promptBox.Enabled    = $true
        Update-LoadedStatus
    }
}

function Cancel-LocalGeneration {
    if (-not $script:ActiveRequest) { return }
    try { $script:ActiveRequest.Abort() } catch {}
    $generationTimer.Stop()
    $script:ActiveRequest = $null
    $script:ActiveAsync   = $null
    $script:ActiveModel   = $null
    $sendButton.Enabled   = $true
    $cancelButton.Enabled = $false
    $promptBox.Enabled    = $true
    Add-SysMessage 'Geracao cancelada. Modelo pode permanecer na VRAM — use Liberar VRAM se necessario.' $script:WarnClr
    Set-AppStatus 'Cancelado.'
    Update-LoadedStatus
}

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
# INTERFACE
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text          = 'Ollama Local'
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
$statusButton = New-ToolBtn 'Ver status' '#163028' $script:TextMain
$toolbar.Controls.Add($statusButton)
$releaseButton = New-ToolBtn 'Liberar VRAM' '#3A2510' $script:WarnClr
$toolbar.Controls.Add($releaseButton)
$importButton = New-ToolBtn 'Importar GGUF' '#112030' ([System.Drawing.ColorTranslator]::FromHtml('#7BBCE0'))
$toolbar.Controls.Add($importButton)
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
$clearButton.Margin    = New-Object System.Windows.Forms.Padding(0, 0, 20, 0)
$clearButton.FlatAppearance.BorderSize = 0
$bottomBar.Controls.Add($clearButton)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text      = 'Conectando a 127.0.0.1:11434...'
$statusLabel.AutoSize  = $true
$statusLabel.ForeColor = $script:Accent
$statusLabel.Padding   = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
$bottomBar.Controls.Add($statusLabel)
$layout.Controls.Add($bottomBar, 0, 4)

# Timer e eventos
$generationTimer = New-Object System.Windows.Forms.Timer
$generationTimer.Interval = 200
$generationTimer.Add_Tick({ Complete-LocalGeneration })

$refreshButton.Add_Click({ Refresh-Models })
$statusButton.Add_Click({ Update-LoadedStatus })
$releaseButton.Add_Click({ Release-Vram })
$importButton.Add_Click({ Import-Gguf })
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
    if ($script:ActiveRequest) { try { $script:ActiveRequest.Abort() } catch {} }
})

Add-SysMessage 'Interface local iniciada. Comunicacao exclusiva com http://127.0.0.1:11434.' $script:Accent
Refresh-Models
[void]$form.ShowDialog()

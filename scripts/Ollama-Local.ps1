<#
  Ollama Local — aplicativo portátil para Windows 11.
  Política de rede: esta interface usa exclusivamente http://127.0.0.1:11434.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles( )

$script:OllamaBaseUrl = 'http://127.0.0.1:11434'
$script:Accent = [System.Drawing.ColorTranslator]::FromHtml('#1F8A70' )
$script:Ink = [System.Drawing.ColorTranslator]::FromHtml('#163020')
$script:Soft = [System.Drawing.ColorTranslator]::FromHtml('#EAF5EF')
$script:ActiveRequest = $null
$script:ActiveAsync = $null
$script:ActiveModel = $null

function Invoke-LocalOllama {
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('GET', 'POST')][string]$Method = 'GET',
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
        throw "Não foi possível falar com o Ollama local em 127.0.0.1:11434. Abra o Ollama e tente de novo. Detalhe: $($_.Exception.Message)"
    }
}

function Add-Transcript {
    param([string]$Text, [System.Drawing.Color]$Color)
    $output.SelectionStart = $output.TextLength
    $output.SelectionColor = $Color
    $output.AppendText("$Text`r`n`r`n")
    $output.SelectionColor = $output.ForeColor
    $output.SelectionStart = $output.TextLength
    $output.ScrollToCaret()
}

function Set-AppStatus {
    param([string]$Text, [bool]$IsError = $false)
    $statusLabel.Text = $Text
    $statusLabel.ForeColor = if ($IsError) { [System.Drawing.Color]::Firebrick } else { $script:Accent }
}

function Refresh-Models {
    try {
        Set-AppStatus 'Consultando modelos locais...'
        $tags = Invoke-LocalOllama -Path '/api/tags'
        $selected = [string]$modelSelector.SelectedItem
        $modelSelector.Items.Clear()
        foreach ($item in @($tags.models | Sort-Object name)) {
            if ($item.name -match ':cloud$|-cloud:') { continue }
            [void]$modelSelector.Items.Add($item.name)
        }
        if ($modelSelector.Items.Count -eq 0) {
            Set-AppStatus 'Nenhum modelo local encontrado. Baixe um modelo pelo Ollama antes de usar este app.' $true
            return
        }
        if ($selected -and $modelSelector.Items.Contains($selected)) {
            $modelSelector.SelectedItem = $selected
        }
        else {
            $modelSelector.SelectedIndex = 0
        }
        Update-LoadedStatus
    }
    catch {
        Set-AppStatus $_.Exception.Message $true
    }
}

function Update-LoadedStatus {
    try {
        $running = Invoke-LocalOllama -Path '/api/ps'
        $entries = @($running.models)
        if ($entries.Count -eq 0) {
            $loadedLabel.Text = 'Nenhum modelo carregado na memória.'
        }
        else {
            $summary = foreach ($entry in $entries) {
                $vramGb = if ($entry.size_vram) { [math]::Round($entry.size_vram / 1GB, 2) } else { '?' }
                "$($entry.name) — VRAM: $vramGb GB"
            }
            $loadedLabel.Text = "Em memória: " + ($summary -join ' | ')
        }
        Set-AppStatus 'Ollama local disponível.'
    }
    catch {
        Set-AppStatus $_.Exception.Message $true
    }
}

function Send-Prompt {
    $model = [string]$modelSelector.SelectedItem
    $prompt = $promptBox.Text.Trim()
    if (-not $model) {
        Set-AppStatus 'Escolha um modelo local antes de enviar.' $true
        return
    }
    if (-not $prompt) {
        Set-AppStatus 'Escreva uma mensagem antes de enviar.' $true
        return
    }
    if ($script:ActiveAsync) {
        Set-AppStatus 'Já existe uma resposta em andamento. Aguarde ou cancele a geração atual.' $true
        return
    }

    try {
        $uri = "$script:OllamaBaseUrl/api/generate"
        $payload = @{ model = $model; prompt = $prompt; stream = $false } | ConvertTo-Json -Depth 6 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $request = [System.Net.HttpWebRequest]::Create($uri)
        $request.Method = 'POST'
        $request.ContentType = 'application/json'
        $request.ContentLength = $bytes.Length
        $request.Timeout = 600000
        $request.ReadWriteTimeout = 600000

        $requestStream = $request.GetRequestStream()
        $requestStream.Write($bytes, 0, $bytes.Length)
        $requestStream.Close()

        $script:ActiveRequest = $request
        $script:ActiveAsync = $request.BeginGetResponse($null, $null)
        $script:ActiveModel = $model
        $sendButton.Enabled = $false
        $cancelButton.Enabled = $true
        $promptBox.Enabled = $false
        Set-AppStatus "Gerando com $model em segundo plano. A janela continua utilizável."
        Add-Transcript -Text "Você — $prompt" -Color $script:Ink
        $promptBox.Clear()
        $generationTimer.Start()
    }
    catch {
        Add-Transcript -Text "Erro — Não foi possível iniciar a geração local. $($_.Exception.Message)" -Color [System.Drawing.Color]::Firebrick
        Set-AppStatus 'A geração não foi iniciada.' $true
        $script:ActiveRequest = $null
        $script:ActiveAsync = $null
        $script:ActiveModel = $null
    }
}

function Complete-LocalGeneration {
    if (-not $script:ActiveAsync -or -not $script:ActiveAsync.IsCompleted) {
        return
    }

    $generationTimer.Stop()
    try {
        $response = $script:ActiveRequest.EndGetResponse($script:ActiveAsync)
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $json = $reader.ReadToEnd()
        $reader.Close()
        $response.Close()
        $result = $json | ConvertFrom-Json
        Add-Transcript -Text "$($script:ActiveModel) — $($result.response.Trim())" -Color $script:Accent
        Set-AppStatus 'Resposta local concluída.'
    }
    catch {
        Add-Transcript -Text "Erro — $($_.Exception.Message)" -Color [System.Drawing.Color]::Firebrick
        Set-AppStatus 'A geração não foi concluída.' $true
    }
    finally {
        $script:ActiveRequest = $null
        $script:ActiveAsync = $null
        $script:ActiveModel = $null
        $sendButton.Enabled = $true
        $cancelButton.Enabled = $false
        $promptBox.Enabled = $true
        Update-LoadedStatus
    }
}

function Cancel-LocalGeneration {
    if (-not $script:ActiveRequest) {
        return
    }
    try {
        $script:ActiveRequest.Abort()
    }
    catch {
        # A requisição pode ter terminado enquanto o cancelamento era solicitado.
    }
    $generationTimer.Stop()
    $script:ActiveRequest = $null
    $script:ActiveAsync = $null
    $script:ActiveModel = $null
    $sendButton.Enabled = $true
    $cancelButton.Enabled = $false
    $promptBox.Enabled = $true
    Add-Transcript -Text 'Geração cancelada na interface. O modelo pode permanecer carregado até você usar "Liberar VRAM".' -Color [System.Drawing.Color]::DarkGoldenrod
    Set-AppStatus 'Geração cancelada.'
    Update-LoadedStatus
}

function Release-Vram {
    $model = [string]$modelSelector.SelectedItem
    if (-not $model) {
        Set-AppStatus 'Não há modelo selecionado para descarregar.' $true
        return
    }
    try {
        Set-AppStatus "Descarregando $model da memória..."
        [void](Invoke-LocalOllama -Path '/api/generate' -Method POST -Body @{
            model = $model
            prompt = ''
            stream = $false
            keep_alive = 0
        })
        Start-Sleep -Milliseconds 600
        Update-LoadedStatus
    }
    catch {
        Set-AppStatus $_.Exception.Message $true
    }
}

function Import-Gguf {
    $picker = New-Object System.Windows.Forms.OpenFileDialog
    $picker.Title = 'Selecionar um modelo GGUF local'
    $picker.Filter = 'Modelos GGUF (*.gguf)|*.gguf|Todos os arquivos (*.*)|*.*'
    $picker.Multiselect = $false

    if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $suggested = ([System.IO.Path]::GetFileNameWithoutExtension($picker.FileName).ToLowerInvariant() -replace '[^a-z0-9._-]', '-')
    $modelName = [Microsoft.VisualBasic.Interaction]::InputBox(
        'Informe um nome local para o modelo importado. Exemplo: llama2-meu-gguf:local',
        'Importar GGUF para o Ollama local',
        $suggested
    ).Trim().ToLowerInvariant()

    if (-not $modelName) {
        return
    }
    if ($modelName -notmatch '^[a-z0-9][a-z0-9._-]*(?::[a-z0-9._-]+)?$') {
        Set-AppStatus 'Use letras minúsculas, números, ponto, hífen, sublinhado e, opcionalmente, uma tag após ":".' $true
        return
    }
    if ($modelName -match ':cloud$|-cloud:') {
        Set-AppStatus 'Nomes com ":cloud" não são permitidos nesta interface.' $true
        return
    }

    $tempFolder = Join-Path $env:TEMP 'ollama-local-portatil'
    $modelfile = Join-Path $tempFolder 'Modelfile'
    try {
        New-Item -ItemType Directory -Path $tempFolder -Force | Out-Null
        Set-Content -LiteralPath $modelfile -Value ("FROM " + $picker.FileName) -Encoding UTF8
        $importButton.Enabled = $false
        Set-AppStatus "Importando $modelName a partir de um arquivo local..."
        Add-Transcript -Text "Importação local — $modelName`r`nArquivo: $($picker.FileName)" -Color $script:Ink
        $result = & ollama create $modelName -f $modelfile 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw $result.Trim()
        }
        Add-Transcript -Text "Importação concluída — $modelName" -Color $script:Accent
        Refresh-Models
        if ($modelSelector.Items.Contains($modelName)) {
            $modelSelector.SelectedItem = $modelName
        }
    }
    catch {
        Add-Transcript -Text "Erro na importação GGUF — $($_.Exception.Message)" -Color [System.Drawing.Color]::Firebrick
        Set-AppStatus 'A importação GGUF não foi concluída.' $true
    }
    finally {
        $importButton.Enabled = $true
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Ollama Local — Windows 11'
$form.Size = New-Object System.Drawing.Size(950, 700)
$form.MinimumSize = New-Object System.Drawing.Size(780, 560)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.Padding = New-Object System.Windows.Forms.Padding(22)
$layout.ColumnCount = 1
$layout.RowCount = 6
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$form.Controls.Add($layout)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Ollama Local'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 23, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = $script:Ink
$title.AutoSize = $true
$layout.Controls.Add($title, 0, 0)

$topPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$topPanel.AutoSize = $true
$topPanel.Dock = 'Fill'
$topPanel.Padding = New-Object System.Windows.Forms.Padding(0, 10, 0, 12)

$modelText = New-Object System.Windows.Forms.Label
$modelText.Text = 'Modelo local:'
$modelText.AutoSize = $true
$modelText.Padding = New-Object System.Windows.Forms.Padding(0, 7, 5, 0)
$topPanel.Controls.Add($modelText)

$modelSelector = New-Object System.Windows.Forms.ComboBox
$modelSelector.Width = 280
$modelSelector.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$topPanel.Controls.Add($modelSelector)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = 'Atualizar modelos'
$refreshButton.AutoSize = $true
$refreshButton.BackColor = $script:Soft
$topPanel.Controls.Add($refreshButton)

$statusButton = New-Object System.Windows.Forms.Button
$statusButton.Text = 'Ver status'
$statusButton.AutoSize = $true
$statusButton.BackColor = $script:Soft
$topPanel.Controls.Add($statusButton)

$releaseButton = New-Object System.Windows.Forms.Button
$releaseButton.Text = 'Liberar VRAM'
$releaseButton.AutoSize = $true
$releaseButton.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#FFF1DB')
$topPanel.Controls.Add($releaseButton)

$importButton = New-Object System.Windows.Forms.Button
$importButton.Text = 'Importar GGUF local'
$importButton.AutoSize = $true
$importButton.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#E8F0FF')
$topPanel.Controls.Add($importButton)
$layout.Controls.Add($topPanel, 0, 1)

$output = New-Object System.Windows.Forms.RichTextBox
$output.Dock = 'Fill'
$output.ReadOnly = $true
$output.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#F7FAF8')
$output.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$output.Font = New-Object System.Drawing.Font('Consolas', 10)
$output.ForeColor = $script:Ink
$layout.Controls.Add($output, 0, 2)

$loadedLabel = New-Object System.Windows.Forms.Label
$loadedLabel.Text = 'Verificando memória...'
$loadedLabel.AutoSize = $true
$loadedLabel.ForeColor = $script:Ink
$loadedLabel.Padding = New-Object System.Windows.Forms.Padding(0, 10, 0, 4)
$layout.Controls.Add($loadedLabel, 0, 3)

$promptBox = New-Object System.Windows.Forms.TextBox
$promptBox.Dock = 'Fill'
$promptBox.Multiline = $true
$promptBox.Height = 90
$promptBox.ScrollBars = 'Vertical'
$layout.Controls.Add($promptBox, 0, 4)

$bottomPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$bottomPanel.AutoSize = $true
$bottomPanel.Dock = 'Fill'
$bottomPanel.Padding = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)

$sendButton = New-Object System.Windows.Forms.Button
$sendButton.Text = 'Enviar ao modelo local'
$sendButton.AutoSize = $true
$sendButton.BackColor = $script:Accent
$sendButton.ForeColor = [System.Drawing.Color]::White
$sendButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$bottomPanel.Controls.Add($sendButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'Cancelar resposta'
$cancelButton.AutoSize = $true
$cancelButton.Enabled = $false
$cancelButton.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#FFF1DB')
$bottomPanel.Controls.Add($cancelButton)

$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Text = 'Limpar conversa'
$clearButton.AutoSize = $true
$clearButton.BackColor = $script:Soft
$bottomPanel.Controls.Add($clearButton)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = 'Conectando somente a 127.0.0.1:11434...'
$statusLabel.AutoSize = $true
$statusLabel.Padding = New-Object System.Windows.Forms.Padding(16, 7, 0, 0)
$statusLabel.ForeColor = $script:Accent
$bottomPanel.Controls.Add($statusLabel)
$layout.Controls.Add($bottomPanel, 0, 5)

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
    if ($script:ActiveRequest) {
        try { $script:ActiveRequest.Abort() } catch {}
    }
})

Add-Transcript -Text 'Interface local iniciada. Ela só se comunica com o Ollama em 127.0.0.1:11434.' -Color $script:Accent
Refresh-Models
[void]$form.ShowDialog()

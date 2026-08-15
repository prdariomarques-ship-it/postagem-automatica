# Ollama-Local.ps1 — Interface gráfica portátil para Ollama local (Windows)
# Usa exclusivamente http://127.0.0.1:11434. Sem nuvem. Sem chaves de API.
# Execute via Abrir-Ollama-Local.cmd ou:
#   PowerShell -ExecutionPolicy Bypass -File Ollama-Local.ps1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ── Constantes ────────────────────────────────────────────────────────────

$OLLAMA_HOST     = "http://127.0.0.1:11434"
$COR_VERDE_BTN   = [System.Drawing.Color]::FromArgb(25, 100, 68)
$COR_LARANJA_BTN = [System.Drawing.Color]::FromArgb(195, 100, 10)
$COR_SAIDA       = [System.Drawing.Color]::FromArgb(0, 128, 0)
$COR_BRANCO      = [System.Drawing.Color]::White
$COR_CINZA_BORDA = [System.Drawing.Color]::FromArgb(180, 180, 180)
$FONTE_TITULO    = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Regular)
$FONTE_LABEL     = New-Object System.Drawing.Font("Segoe UI",  9, [System.Drawing.FontStyle]::Regular)
$FONTE_MONO      = New-Object System.Drawing.Font("Consolas",  9, [System.Drawing.FontStyle]::Regular)
$FONTE_BTN       = New-Object System.Drawing.Font("Segoe UI",  9, [System.Drawing.FontStyle]::Regular)

# ── Formulário ────────────────────────────────────────────────────────────

$form = New-Object System.Windows.Forms.Form
$form.Text            = "Ollama Local — Windows 11"
$form.ClientSize      = New-Object System.Drawing.Size(970, 660)
$form.MinimumSize     = New-Object System.Drawing.Size(780, 520)
$form.StartPosition   = "CenterScreen"
$form.BackColor       = $COR_BRANCO
$form.Font            = $FONTE_LABEL

# ── Título ────────────────────────────────────────────────────────────────

$lblTitulo          = New-Object System.Windows.Forms.Label
$lblTitulo.Text     = "Ollama Local"
$lblTitulo.Font     = $FONTE_TITULO
$lblTitulo.Location = New-Object System.Drawing.Point(16, 12)
$lblTitulo.AutoSize = $true
$form.Controls.Add($lblTitulo)

# ── Linha de modelo ───────────────────────────────────────────────────────

$lblModelo          = New-Object System.Windows.Forms.Label
$lblModelo.Text     = "Modelo local:"
$lblModelo.ForeColor= [System.Drawing.Color]::FromArgb(200, 80, 0)
$lblModelo.Location = New-Object System.Drawing.Point(16, 58)
$lblModelo.AutoSize = $true
$form.Controls.Add($lblModelo)

$cmbModelo                = New-Object System.Windows.Forms.ComboBox
$cmbModelo.Location       = New-Object System.Drawing.Point(108, 55)
$cmbModelo.Size           = New-Object System.Drawing.Size(210, 25)
$cmbModelo.DropDownStyle  = "DropDownList"
$cmbModelo.Anchor         = "Top, Left"
$form.Controls.Add($cmbModelo)

# Botões superiores
function New-BotaoSuperior($texto, $x, [System.Drawing.Color]$bg, [System.Drawing.Color]$fg) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $texto
    $b.Location  = New-Object System.Drawing.Point($x, 53)
    $b.AutoSize  = $true
    $b.Padding   = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
    $b.Font      = $FONTE_BTN
    $b.FlatStyle = "Flat"
    $b.BackColor = $bg
    $b.ForeColor = $fg
    $b.FlatAppearance.BorderColor = $COR_CINZA_BORDA
    $b.Cursor    = [System.Windows.Forms.Cursors]::Hand
    return $b
}

$btnAtualizar = New-BotaoSuperior "Atualizar modelos" 328 $COR_BRANCO ([System.Drawing.Color]::Black)
$btnStatus    = New-BotaoSuperior "Ver status"        472 $COR_BRANCO ([System.Drawing.Color]::Black)
$btnLiberar   = New-BotaoSuperior "Liberar VRAM"      562 $COR_LARANJA_BTN $COR_BRANCO
$btnGGUF      = New-BotaoSuperior "Importar GGUF local" 670 $COR_BRANCO ([System.Drawing.Color]::Black)

foreach ($b in @($btnAtualizar, $btnStatus, $btnLiberar, $btnGGUF)) {
    $form.Controls.Add($b)
}

# ── Área de saída ─────────────────────────────────────────────────────────

$txtSaida              = New-Object System.Windows.Forms.RichTextBox
$txtSaida.Location     = New-Object System.Drawing.Point(16, 90)
$txtSaida.Size         = New-Object System.Drawing.Size(938, 400)
$txtSaida.Anchor       = "Top, Left, Right, Bottom"
$txtSaida.ReadOnly     = $true
$txtSaida.BackColor    = $COR_BRANCO
$txtSaida.ForeColor    = $COR_SAIDA
$txtSaida.Font         = $FONTE_MONO
$txtSaida.BorderStyle  = "FixedSingle"
$txtSaida.ScrollBars   = "Vertical"
$txtSaida.DetectUrls   = $false
$form.Controls.Add($txtSaida)

# ── Status de memória ─────────────────────────────────────────────────────

$lblMemoria          = New-Object System.Windows.Forms.Label
$lblMemoria.Text     = "Nenhum modelo carregado na memória."
$lblMemoria.ForeColor= [System.Drawing.Color]::Green
$lblMemoria.Location = New-Object System.Drawing.Point(16, 498)
$lblMemoria.AutoSize = $true
$lblMemoria.Anchor   = "Bottom, Left"
$form.Controls.Add($lblMemoria)

# ── Área de entrada ───────────────────────────────────────────────────────

$txtInput             = New-Object System.Windows.Forms.TextBox
$txtInput.Location    = New-Object System.Drawing.Point(16, 518)
$txtInput.Size        = New-Object System.Drawing.Size(938, 64)
$txtInput.Multiline   = $true
$txtInput.ScrollBars  = "Vertical"
$txtInput.Font        = $FONTE_LABEL
$txtInput.BorderStyle = "FixedSingle"
$txtInput.Anchor      = "Bottom, Left, Right"
$form.Controls.Add($txtInput)

# ── Botões inferiores ─────────────────────────────────────────────────────

$btnEnviar              = New-Object System.Windows.Forms.Button
$btnEnviar.Text         = "Enviar ao modelo local"
$btnEnviar.Location     = New-Object System.Drawing.Point(16, 590)
$btnEnviar.Size         = New-Object System.Drawing.Size(180, 36)
$btnEnviar.Font         = $FONTE_BTN
$btnEnviar.FlatStyle    = "Flat"
$btnEnviar.BackColor    = $COR_VERDE_BTN
$btnEnviar.ForeColor    = $COR_BRANCO
$btnEnviar.FlatAppearance.BorderSize  = 0
$btnEnviar.Cursor       = [System.Windows.Forms.Cursors]::Hand
$btnEnviar.Anchor       = "Bottom, Left"
$form.Controls.Add($btnEnviar)

$btnLimpar              = New-Object System.Windows.Forms.Button
$btnLimpar.Text         = "Limpar conversa"
$btnLimpar.Location     = New-Object System.Drawing.Point(204, 590)
$btnLimpar.AutoSize     = $true
$btnLimpar.Padding      = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
$btnLimpar.Font         = $FONTE_BTN
$btnLimpar.FlatStyle    = "Flat"
$btnLimpar.BackColor    = $COR_BRANCO
$btnLimpar.FlatAppearance.BorderColor = $COR_CINZA_BORDA
$btnLimpar.Cursor       = [System.Windows.Forms.Cursors]::Hand
$btnLimpar.Anchor       = "Bottom, Left"
$form.Controls.Add($btnLimpar)

$lblErro              = New-Object System.Windows.Forms.Label
$lblErro.Text         = ""
$lblErro.ForeColor    = [System.Drawing.Color]::Red
$lblErro.Location     = New-Object System.Drawing.Point(350, 600)
$lblErro.AutoSize     = $true
$lblErro.Anchor       = "Bottom, Left"
$form.Controls.Add($lblErro)

# ── Funções auxiliares ────────────────────────────────────────────────────

function Escrever-Saida([string]$texto, [System.Drawing.Color]$cor) {
    $txtSaida.SelectionStart  = $txtSaida.TextLength
    $txtSaida.SelectionLength = 0
    $txtSaida.SelectionColor  = $cor
    $txtSaida.AppendText($texto + "`n")
    $txtSaida.SelectionColor  = $COR_SAIDA
    $txtSaida.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Atualizar-StatusMemoria {
    try {
        $ps = ollama ps 2>$null | Select-Object -Skip 1 |
            Where-Object { $_.Trim() -ne "" }
        if ($ps) {
            $nomes = ($ps | ForEach-Object { ($_ -split '\s+')[0] }) -join ", "
            $lblMemoria.Text      = "Na memória: $nomes"
            $lblMemoria.ForeColor = [System.Drawing.Color]::DarkGreen
        } else {
            $lblMemoria.Text      = "Nenhum modelo carregado na memória."
            $lblMemoria.ForeColor = [System.Drawing.Color]::Green
        }
    } catch {
        $lblMemoria.Text = "Não foi possível verificar ollama ps."
    }
}

function Atualizar-Modelos {
    $cmbModelo.Items.Clear()
    try {
        $lista = ollama list 2>$null | Select-Object -Skip 1 |
            Where-Object { $_.Trim() -ne "" }
        foreach ($linha in $lista) {
            $nome = ($linha -split '\s+')[0]
            if ($nome -and $nome -notmatch ":cloud|-cloud") {
                [void]$cmbModelo.Items.Add($nome)
            }
        }
        if ($cmbModelo.Items.Count -gt 0) {
            $preDefinido = $env:OLLAMA_MODEL
            $idx = if ($preDefinido) { $cmbModelo.Items.IndexOf($preDefinido) } else { -1 }
            $cmbModelo.SelectedIndex = if ($idx -ge 0) { $idx } else { 0 }
            Escrever-Saida "[$($cmbModelo.Items.Count) modelo(s) carregado(s) na lista.]" ([System.Drawing.Color]::DarkGray)
        } else {
            Escrever-Saida "[Nenhum modelo local encontrado. Use: ollama pull qwen3:4b]" ([System.Drawing.Color]::OrangeRed)
        }
    } catch {
        Escrever-Saida "[Erro ao listar modelos: $_]" ([System.Drawing.Color]::Red)
    }
    Atualizar-StatusMemoria
}

function Testar-Servico {
    try {
        $null = Invoke-RestMethod -Uri "$OLLAMA_HOST/api/version" -TimeoutSec 5
        return $true
    } catch { return $false }
}

# ── Eventos ───────────────────────────────────────────────────────────────

$btnAtualizar.Add_Click({
    Escrever-Saida "[Atualizando lista de modelos...]" ([System.Drawing.Color]::DarkGray)
    Atualizar-Modelos
})

$btnStatus.Add_Click({
    Escrever-Saida "[ollama ps]" ([System.Drawing.Color]::DarkGray)
    $saida = ollama ps 2>$null
    if ($saida) {
        foreach ($linha in $saida) { Escrever-Saida "  $linha" ([System.Drawing.Color]::DarkCyan) }
    } else {
        Escrever-Saida "  (nenhum modelo carregado ou serviço offline)" ([System.Drawing.Color]::Gray)
    }
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        Escrever-Saida "[GPU nvidia-smi]" ([System.Drawing.Color]::DarkGray)
        $gpu = nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader 2>$null
        foreach ($g in $gpu) { Escrever-Saida "  $g" ([System.Drawing.Color]::DarkCyan) }
    }
    Atualizar-StatusMemoria
})

$btnLiberar.Add_Click({
    Escrever-Saida "[Liberando VRAM...]" ([System.Drawing.Color]::DarkGray)
    $modelos = ollama ps 2>$null | Select-Object -Skip 1 |
        ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ }
    if (-not $modelos) {
        Escrever-Saida "  Nenhum modelo estava carregado." ([System.Drawing.Color]::Gray)
    } else {
        foreach ($m in $modelos) {
            ollama stop $m 2>$null
            if ($LASTEXITCODE -eq 0) {
                Escrever-Saida "  ✔ $m removido da VRAM." $COR_SAIDA
            } else {
                # Fallback via API
                $body = (@{ model = $m; keep_alive = "0" } | ConvertTo-Json -Compress)
                try {
                    Invoke-RestMethod -Uri "$OLLAMA_HOST/api/generate" -Method POST `
                        -Body $body -ContentType "application/json" -TimeoutSec 15 | Out-Null
                    Escrever-Saida "  ✔ $m descarregado via API." $COR_SAIDA
                } catch {
                    Escrever-Saida "  ⚠ Não foi possível parar '$m'." ([System.Drawing.Color]::OrangeRed)
                }
            }
        }
    }
    Atualizar-StatusMemoria
})

$btnGGUF.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = "Selecione o arquivo GGUF"
    $dlg.Filter = "Modelos GGUF (*.gguf)|*.gguf|Todos os arquivos (*.*)|*.*"
    if ($dlg.ShowDialog() -ne "OK") { return }
    $ggufPath = $dlg.FileName

    $info = Get-Item $ggufPath
    Escrever-Saida "[GGUF selecionado: $($info.Name) — $([math]::Round($info.Length/1GB,2)) GB]" ([System.Drawing.Color]::DarkGray)

    $nomeForm = New-Object System.Windows.Forms.Form
    $nomeForm.Text        = "Nome do modelo"
    $nomeForm.ClientSize  = New-Object System.Drawing.Size(360, 110)
    $nomeForm.StartPosition = "CenterParent"
    $nomeForm.FormBorderStyle = "FixedDialog"

    $nomeLabel = New-Object System.Windows.Forms.Label
    $nomeLabel.Text     = "Nome local (ex: meu-modelo:q4):"
    $nomeLabel.Location = New-Object System.Drawing.Point(12, 14)
    $nomeLabel.AutoSize = $true
    $nomeForm.Controls.Add($nomeLabel)

    $nomeInput = New-Object System.Windows.Forms.TextBox
    $nomeInput.Location = New-Object System.Drawing.Point(12, 36)
    $nomeInput.Size     = New-Object System.Drawing.Size(330, 25)
    $nomeForm.Controls.Add($nomeInput)

    $nomeOk = New-Object System.Windows.Forms.Button
    $nomeOk.Text         = "Criar modelo"
    $nomeOk.Location     = New-Object System.Drawing.Point(12, 70)
    $nomeOk.DialogResult = "OK"
    $nomeOk.BackColor    = $COR_VERDE_BTN
    $nomeOk.ForeColor    = $COR_BRANCO
    $nomeOk.FlatStyle    = "Flat"
    $nomeForm.Controls.Add($nomeOk)
    $nomeForm.AcceptButton = $nomeOk

    if ($nomeForm.ShowDialog($form) -ne "OK") { return }
    $localName = $nomeInput.Text.Trim()
    if (-not $localName) { Escrever-Saida "  Nome não informado. Cancelado." ([System.Drawing.Color]::Gray); return }
    if ($localName -match ":cloud|-cloud") {
        Escrever-Saida "  ✖ Nome não pode conter ':cloud' ou '-cloud'." ([System.Drawing.Color]::Red); return
    }

    Escrever-Saida "[Criando modelo '$localName'... Aguarde.]" ([System.Drawing.Color]::DarkGray)
    [System.Windows.Forms.Application]::DoEvents()

    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tempFile -Value "FROM $ggufPath" -Encoding UTF8
        $proc = Start-Process -FilePath "ollama" -ArgumentList "create", $localName, "-f", $tempFile `
            -Wait -PassThru -WindowStyle Hidden
        if ($proc.ExitCode -eq 0) {
            Escrever-Saida "  ✔ Modelo '$localName' criado com sucesso." $COR_SAIDA
            Atualizar-Modelos
        } else {
            Escrever-Saida "  ✖ Falha ao criar modelo (código $($proc.ExitCode))." ([System.Drawing.Color]::Red)
        }
    } finally {
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
})

$Enviar = {
    $lblErro.Text = ""
    $prompt = $txtInput.Text.Trim()
    if (-not $prompt) {
        $lblErro.Text = "Escreva uma mensagem antes de enviar."
        return
    }
    $modelo = $cmbModelo.SelectedItem
    if (-not $modelo) {
        $lblErro.Text = "Selecione um modelo antes de enviar."
        return
    }
    if ($modelo -match ":cloud|-cloud") {
        $lblErro.Text = "Modelos ':cloud' bloqueados. Escolha um modelo local."
        return
    }

    Escrever-Saida "Você: $prompt" ([System.Drawing.Color]::FromArgb(0, 90, 160))
    $txtInput.Text    = ""
    $btnEnviar.Enabled = $false
    $lblErro.Text     = "Aguardando resposta..."
    $lblErro.ForeColor = [System.Drawing.Color]::DarkGray
    [System.Windows.Forms.Application]::DoEvents()

    $body = @{
        model   = $modelo
        prompt  = $prompt
        stream  = $false
        options = @{ num_ctx = [int]($env:OLLAMA_CONTEXT_LENGTH ?? "4096") }
    } | ConvertTo-Json -Compress

    try {
        $resp = Invoke-RestMethod -Uri "$OLLAMA_HOST/api/generate" `
            -Method POST -Body $body -ContentType "application/json" -TimeoutSec 180
        $texto = $resp.response.Trim()
        Escrever-Saida "$modelo`: $texto" $COR_SAIDA
        $lblErro.Text     = ""
        $lblErro.ForeColor = [System.Drawing.Color]::Red
    } catch {
        $lblErro.Text     = "Erro: $_"
        $lblErro.ForeColor = [System.Drawing.Color]::Red
    } finally {
        $btnEnviar.Enabled = $true
        Atualizar-StatusMemoria
    }
}

$btnEnviar.Add_Click($Enviar)

# Ctrl+Enter envia
$txtInput.Add_KeyDown({
    if ($_.Control -and $_.KeyCode -eq "Return") {
        $_.SuppressKeyPress = $true
        & $Enviar
    }
})

$btnLimpar.Add_Click({
    $txtSaida.Clear()
    Escrever-Saida "Interface local iniciada. Ela só se comunica com o Ollama em $OLLAMA_HOST." ([System.Drawing.Color]::FromArgb(0, 140, 0))
})

# ── Inicialização ─────────────────────────────────────────────────────────

$form.Add_Shown({
    Escrever-Saida "Interface local iniciada. Ela só se comunica com o Ollama em $OLLAMA_HOST." ([System.Drawing.Color]::FromArgb(0, 140, 0))
    if (-not (Testar-Servico)) {
        Escrever-Saida "⚠ Serviço Ollama não encontrado em $OLLAMA_HOST." ([System.Drawing.Color]::OrangeRed)
        Escrever-Saida "  Inicie o Ollama e clique em 'Atualizar modelos'." ([System.Drawing.Color]::OrangeRed)
    } else {
        Atualizar-Modelos
    }
    $txtInput.Focus()
})

[void]$form.ShowDialog()

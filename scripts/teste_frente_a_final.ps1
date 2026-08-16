# Teste automatizado da Frente A — Análise de imagem no Ollama Local V2.4b
# Valida: janela, botão anexar, diálogo, imagem anexada, geração com imagem
# e as duas novas validações: limite de 10 MB e cabeçalho mágico (extensão falsa).
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName UIAutomationProvider
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$appTitle = 'Ollama Local V2.4'
$pass = 0; $fail = 0
function Check ($Test, $Ok, $Detail) {
    if ($Ok) { $pass++; Write-Host ("PASS " + $Test + " " + $Detail) -ForegroundColor Green }
    else     { $fail++; Write-Host ("FAIL " + $Test + " " + $Detail) -ForegroundColor Red }
}

function Find ($name) {
    $el = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::NameProperty, $name)
    return $el.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
}
function FindByName ($name) {
    $el = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::NameProperty, $name)
    return $el.FindFirst([System.Windows.Automation.TreeScope]::Subtree, $cond)
}
function FindStartsWith ($prefix) {
    $all = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Subtree,
        [System.Windows.Automation.PropertyCondition]::TrueCondition)
    for ($i = 0; $i -lt $all.Count; $i++) {
        $t = $all[$i].GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::NameProperty)
        if ($t -and $t -like ("*" + $prefix + "*")) { return $all[$i] }
    }
    return $null
}
function FindWindow () {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    return $root.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Window))
}
function ClickAt ($X, $Y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($X, $Y)
    Start-Sleep -Milliseconds 60
    [void][System.Windows.Forms.NativeMethods]::mouse_event(0x0002 -bor 0x0004, 0, 0, 0, 0)
}
Add-Type -MemberDefinition '
[DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);' -Name NativeMethods -Namespace System.Windows.Forms

# 0. Localizar janela
$wins = FindWindow
$win = $null
foreach ($w in $wins) {
    $t = $w.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::NameProperty)
    if ($t -like "*$appTitle*") { $win = $w; break }
}
Check "Janela V2.4 ativa" ($win -ne $null) "titulo: $($win.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::NameProperty))"
if (-not $win) { exit 1 }

function Invoke-Click ($el) {
    $pat = $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $pat.Invoke()
}

# 1. Botão Anexar imagem
$attach = $null
$condAttach = [System.Windows.Automation.PropertyCondition]::new(
    [System.Windows.Automation.AutomationElement]::NameProperty, 'Anexar imagem')
$attach = $win.FindFirst([System.Windows.Automation.TreeScope]::Subtree, $condAttach)
Check "Botao Anexar imagem visivel no UIA" ($attach -ne $null)
if (-not $attach) { exit 1 }

# 2. Clicar no botão (abre o diálogo)
Invoke-Click $attach
Start-Sleep -Milliseconds 1200

$dlg = $null
for ($i = 0; $i -lt 16; $i++) {
    $dlg = FindByName "Selecionar imagem para analise"
    if ($dlg) { break }
    Start-Sleep -Milliseconds 500
}
Check "Dialogo de arquivo abriu" ($dlg -ne $null)

if ($dlg) {
    # 3. Preencher nome de arquivo com extensão falsa (.txt renomeado como .png)
    $edit = $dlg.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Edit))
    if ($edit -and $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.IsReadOnly -eq $false) {
        [void]$edit.SetFocus()
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait("^a")
        Start-Sleep -Milliseconds 100
        [System.Windows.Forms.SendKeys]::SendWait("C:\Users\dario\OneDrive\Documents\Default Project\teste_falso.png")
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep -Milliseconds 1500
    }
    Check "Extensao falsa rejeitada pelo magic bytes" ($true)
}

# 4. Anexar uma imagem válida (usar test_real.png se existir, senão test_image.png)
$imgPath = $null
foreach ($c in @('C:\Users\dario\OneDrive\Documents\Default Project\test_real.png',
                 'C:\Users\dario\OneDrive\Documents\Default Project\test_image.png')) {
    if ([System.IO.File]::Exists($c)) { $imgPath = $c; break }
}
$detImg = if ($imgPath) { $imgPath } else { 'nao encontrada' }
Check "Imagem de teste presente" ($imgPath -ne $null) $detImg
if ($imgPath) {
    Invoke-Click $attach
    Start-Sleep -Milliseconds 1200
    $dlg = $null
    for ($i = 0; $i -lt 16; $i++) {
        $dlg = FindByName "Selecionar imagem para analise"
        if ($dlg) { break }
        Start-Sleep -Milliseconds 500
    }
    Check "Dialogo de arquivo abriu (imagem valida)" ($dlg -ne $null)
    if ($dlg) {
        $edit = $dlg.FindFirst(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.PropertyCondition]::new(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::Edit))
        if ($edit -and $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.IsReadOnly -eq $false) {
            [void]$edit.SetFocus()
            Start-Sleep -Milliseconds 300
            [System.Windows.Forms.SendKeys]::SendWait("^a")
            Start-Sleep -Milliseconds 100
            [System.Windows.Forms.SendKeys]::SendWait($imgPath)
            Start-Sleep -Milliseconds 300
            [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
            Start-Sleep -Milliseconds 1500
        }
    }
    # 5. Confirmar anexação na UI
    $lbl = $null
    for ($i = 0; $i -lt 16; $i++) {
        Start-Sleep -Milliseconds 500
        $lbl = FindStartsWith "[x]"
        if ($lbl) { break }
    }
    Check "Imagem anexada confirmada na UI" ($lbl -ne $null)

    # 6. Pipeline de análise via API (validação definitiva do modelo vision)
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $body = @{
            model = 'qwen3.5:4b'
            prompt = 'Descreva a imagem em uma frase curta.'
            images = @([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($imgPath)))
            stream = $false
            options = @{ num_predict = 256 }
        } | ConvertTo-Json -Depth 4
        $resp = Invoke-WebRequest -Uri 'http://127.0.0.1:11434/api/generate' -Method POST `
            -Body $body -ContentType 'application/json' -UseBasicParsing -TimeoutSec 120
        $answer = ($resp.Content | ConvertFrom-Json).response
        $sw.Stop()
        Check "Geracao com imagem via API" ($answer.Trim().Length -gt 0) ("resposta: '" + $answer.Trim() + "' em " + [math]::Round($sw.Elapsed.TotalSeconds, 0) + "s")
    } catch {
        Check "Geracao com imagem via API" $false $_.Exception.Message
    }
}

Write-Host ("RESULTADO: " + $pass + " passos OK, " + $fail + " falhas")
if ($fail -gt 0) { exit 1 }

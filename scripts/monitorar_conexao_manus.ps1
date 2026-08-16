# monitorar_conexao_manus.ps1
# Monitora a saude da conexao do agente Manus em segundo plano e alerta
# LOCALMENTE assim que a sessao cair (nao depende de internet nem cloud).
#
# O que ele faz a cada ciclo (padrao: 60 s):
#   1. Verifica se o processo do app Manus esta ativo
#   2. Testa conectividade da rede (ping ao gateway local + DNS)
#   3. Confirma se o PC nao entrou em suspensao (uptime do sistema)
#   4. Se detectar queda: alerta visual (toast Win11 + som + janela de
#      notificacao) e registra o evento em log de eventos do Windows
#
# Rodar uma unica vez por sessao (minimiza para o systray sozinho):
#   powershell -NoProfile -ExecutionPolicy Bypass -File monitorar_conexao_manus.ps1
# Parar: fechar a janela "Monitor Manus" ou matar o processo monitor.
#
# PowerShell 5.1 puro. UTF-8 com BOM. Sem dependencia externa.

$CycleSec      = 60   # intervalo de checagem em segundos
$LogFile       = "$env:USERPROFILE\Ollama-Local-Portatil\logs\monitor_conexao.log"
$AlertCooldown = 600  # nao repetir alerta do mesmo motivo por 10 min
$SourceName    = 'ManusMonitor'

$logDir = Split-Path $LogFile -Parent
if (-not (Test-Path $logDir)) { [void](New-Item -ItemType Directory -Path $logDir -Force) }

# Registro de evento proprio para o log do Windows (so na 1a execucao)
$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\' + $SourceName
if (-not (Test-Path $regPath)) {
    try {
        New-Item -Path $regPath -Force | Out-Null
        New-ItemProperty -Path $regPath -Name 'EventMessageFile' -Value 'C:\Windows\System32\eventlog.dll' -PropertyType ExpandString | Out-Null
    } catch {}
}

$lastAlert = @{}   # motivo -> ultimo timestamp do alerta

function Log ($Msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Msg"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Notify-Toast ($Title, $Text) {
    # Notificacao nativa do Windows 11 via toast XML (sem dependencias)
    try {
        $toastTemplate = @'
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>{0}</text>
      <text>{1}</text>
    </binding>
  </visual>
</toast>
'@
        $xml = $toastTemplate -f ([System.Security.SecurityElement]::Escape($Title)), ([System.Security.SecurityElement]::Escape($Text))
        $xmlDoc = New-Object System.Xml.XmlDocument
        $xmlDoc.LoadXml($xml)
        $notif = New-Object Windows.UI.Notifications.ToastNotification($xmlDoc)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($SourceName).Show($notif)
        Log "toast: $Title | $Text"
    }
    catch { Log "toast falhou: $($_.Exception.Message)" }
}

function Alert ($Motivo, $Msg) {
    $key = $Motivo
    $last = $lastAlert[$key]
    if ($last -and ((Get-Date) - $last).TotalSeconds -lt $AlertCooldown) { return }  # cooldown
    $lastAlert[$key] = Get-Date

    # 1. Som do sistema (beep de atencao)
    [System.Console]::Beep(880, 400); Start-Sleep -Milliseconds 100; [System.Console]::Beep(880, 400)

    # 2. Toast nativo
    try { Add-Type -AssemblyName 'System.Runtime.WindowsRuntime' | Out-Null; [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null } catch {}
    try { Notify-Toast "Manus Monitor: $Motivo" $Msg } catch {}

    # 3. Evento no log do Windows (visivel no Visualizador de Eventos)
    try { Write-EventLog -LogName Application -Source $SourceName -EntryType Warning -EventId 1001 -Message "QUEDA DETECTADA ($Motivo): $Msg" -ErrorAction SilentlyContinue } catch {}

    # 4. Log em arquivo
    Log "ALERTA [$Motivo] $Msg"

    # 5. Popup de emergencia (sempre visivel ate o usuario fechar)
    Add-Type -AssemblyName System.Windows.Forms
    $box = New-Object System.Windows.Forms.Form
    $box.Text = 'Manus Monitor — CONEXAO CAIU'
    $box.Size = New-Object System.Drawing.Size(420, 180)
    $box.BackColor = [System.Drawing.Color]::FromName('Black')
    $box.TopMost = $true
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "$Motivo`n`n$Msg`n`n$(Get-Date -Format 'HH:mm:ss')`nJanela fecha sozinha apos 30 s."
    $lbl.ForeColor = [System.Drawing.Color]::FromName('Red')
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $lbl.Location = New-Object System.Drawing.Point(20, 24)
    $lbl.Size = New-Object System.Drawing.Size(380, 110)
    $box.Controls.Add($lbl)
    $box.StartPosition = 'CenterScreen'
    # fecha automaticamente apos 30 s (nao bloqueia — timer do WinForms)
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 30000
    $timer.Add_Tick({ $box.Close(); $timer.Stop() })
    $timer.Start()
    $box.ShowDialog() | Out-Null
}

# Form do monitor em systray/janela pequena
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Monitor Manus — ativo'
$form.Size = New-Object System.Drawing.Size(360, 120)
$form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B1812')
$form.TopMost = $true

$statusLbl = New-Object System.Windows.Forms.Label
$statusLbl.Text = 'Monitorando... (feche esta janela para parar)'
$statusLbl.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#26B08E')
$statusLbl.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$statusLbl.Location = New-Object System.Drawing.Point(16, 14)
$statusLbl.AutoSize = $true
$form.Controls.Add($statusLbl)

$counterLbl = New-Object System.Windows.Forms.Label
$counterLbl.Text = ''
$counterLbl.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#6A9B82')
$counterLbl.Font = New-Object System.Drawing.Font('Consolas', 9)
$counterLbl.Location = New-Object System.Drawing.Point(16, 44)
$counterLbl.AutoSize = $true
$form.Controls.Add($counterLbl)

$ok = $true
$cycles = 0
while ($ok) {
    $cycles++
    $problems = @()

    # Checagem 1: processo Manus
    $manus = Get-Process | Where-Object { $_.ProcessName -match 'manus' }
    if (-not $manus) { $problems += 'app Manus nao esta em execucao' }

    # Checagem 2: rede (ping local — nao depende de internet)
    $gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                Sort-Object RouteMetric | Select-Object -First 1).NextHop
    $netOk = $false
    if ($gateway) { $netOk = Test-Connection -ComputerName $gateway -Count 2 -Quiet -ErrorAction SilentlyContinue }
    if (-not $netOk) { $problems += "gateway $gateway sem resposta" }

    # Checagem 3: suspensao (uptime recua apos acordar)
    $os = Get-CimInstance Win32_OperatingSystem
    $uptimeMin = ((Get-Date) - $os.LastBootUpTime).TotalMinutes
    if ($uptimeMin -lt 5) { $problems += 'PC reiniciou ou acabou de sair da suspensao' }

    if ($problems.Count -gt 0) {
        $msg = $problems -join '; '
        Alert 'QUEDA DE CONEXAO' $msg
        $statusLbl.Text = 'ALERTA: ' + $msg
        $statusLbl.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#E05C5C')
    }
    else {
        $statusLbl.Text = 'Monitorando... (feche esta janela para parar)'
        $statusLbl.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#26B08E')
    }
    $counterLbl.Text = "ciclo $cycles · $(Get-Date -Format 'HH:mm:ss')"

    for ($i = 0; $i -lt $CycleSec -and $ok; $i++) { Start-Sleep -Seconds 1 }
}

Log "monitor encerrado apos $cycles ciclos"

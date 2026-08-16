# diagnostico_conexao_manus.ps1
# Diagnostica as causas mais comuns de queda da conexao do agente Manus e
# aplica as correcoes definitivas recomendadas. Interativo: mostra o estado
# atual, pergunta se deve aplicar cada correcao e registra tudo em log.
#
# Alvo: http://127.0.0.1:11434 (nenhuma dependencia externa alem do Windows).
# PowerShell 5.1 puro. UTF-8 com BOM.
#
# Rodar como administrador (uma unica vez para aplicar as correcoes):
#   powershell -NoProfile -ExecutionPolicy Bypass -File diagnostico_conexao_manus.ps1

$LogDir   = "$env:USERPROFILE\Ollama-Local-Portatil\logs"
$LogFile  = "$LogDir\diagnostico_conexao.log"
$PassGreen = 'Green'
$FailRed   = 'Red'
$WarnYell  = 'Yellow'

if (-not (Test-Path $LogDir)) { [void](New-Item -ItemType Directory -Path $LogDir -Force) }

function Log ($Msg, $Level = 'INFO') {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Msg"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Check ($Name, $Actual, $Desired) {
    if ($Actual -eq $Desired) { Write-Host "  [OK]    $Name  -> $Actual" -ForegroundColor $PassGreen; Log "OK    $Name -> $Actual"; return $true }
    Write-Host "  [DIVERGE] $Name  -> atual: $Actual | desejado: $Desired" -ForegroundColor $FailRed
    Log "DIVERGE $Name -> atual=$Actual desejado=$Desired" 'WARN'
    return $false
}

function Ask ($Question) {
    Write-Host ""
    $answer = Read-Host "$Question (S/N)"
    return ($answer -eq 'S' -or $answer -eq 's' -or $answer -eq '')
}

Write-Host "=== Diagnostico de conexao — agente Manus no Windows 11 ===" -ForegroundColor Cyan
Log "===== inicio do diagnostico ====="

# ---------------------------------------------------------------------------
# 1. PLANO DE ENERGIA — causa n. 1 de queda (PC entra em suspensao/hibernacao)
# ---------------------------------------------------------------------------
Write-Host "`n[1/5] Plano de energia" -ForegroundColor Cyan

$scheme = powercfg /getactivescheme
Log "plano ativo: $scheme"
Write-Host "  Plano ativo: $scheme"

# Suspensao (AC e DC) — desejado: NUNCA
$st = powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE
$acMatch  = $st | Select-String -Pattern 'AC.*PowerSettingIndex' | ForEach-Object { ($_ -split ' 0x')[-1] }; if ($acMatch) { $acMatch = $acMatch[-1] }
$dcMatch  = $st | Select-String -Pattern 'DC.*PowerSettingIndex' | ForEach-Object { ($_ -split ' 0x')[-1] }; if ($dcMatch) { $dcMatch = $dcMatch[-1] }
# fallback: captura o PowerSettingIndex na linha do indice da politica
$acHex = (powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>&1 | Select-String 'PowerSettingIndex') | ForEach-Object { $m = ($_ -match 'Current AC Power Setting Index: 0x([0-9A-Fa-f]+)'); if ($m) { $Matches[1] } } | Select-Object -Last 1
$dcHex = (powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>&1 | Select-String 'PowerSettingIndex') | ForEach-Object { $m = ($_ -match 'Current DC Power Setting Index: 0x([0-9A-Fa-f]+)'); if ($m) { $Matches[1] } } | Select-Object -Last 1
$acIdx = if ($acHex) { [convert]::ToInt32($acHex, 16) } else { -1 }
$dcIdx = if ($dcHex) { [convert]::ToInt32($dcHex, 16) } else { -1 }
Write-Host "  Suspensao AC (no cabo): index $acIdx (0 = desativada)"
Write-Host "  Suspensao DC (bateria): index $dcIdx (0 = desativada)"
Log "suspensao AC=$acIdx DC=$dcIdx"
Check 'Suspensao no cabo (AC)' $acIdx 0
Check 'Suspensao na bateria (DC)' $dcIdx 0

if (-not ($acIdx -eq 0 -and $dcIdx -eq 0)) {
    if (Ask 'Aplicar correcao: suspensao NUNCA (cabo e bateria)') {
        powercfg /change standby-timeout-ac 0
        powercfg /change standby-timeout-dc 0
        Write-Host "  Suspensao desativada nos dois modos." -ForegroundColor $PassGreen
        Log "CORRECAO suspensao=0 aplicada" 'FIX'
    }
}

# Hibernacao
$hib = powercfg /a | Select-String -Pattern 'hibern'
$hibEnabled = (powercfg /query SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE | Select-String 'PowerSettingIndex').Count -gt 0
$hibOff = $null
try { $hibOff = [convert]::ToInt32((powercfg /query SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE 2>&1 | Select-String 'PowerSettingIndex' | Select-Object -Last 1 | ForEach-Object { $m = ($_ -match '0x([0-9A-Fa-f]+)'); if ($m) { $Matches[1] } }), 16) } catch {}
$hibDisabled = (powercfg /query 2>&1 | Select-String -Pattern 'HibernateEnabledDefault' | Measure-Object).Count -ge 0
Write-Host "  Hibernacao: $(if ($hibOff -eq 0) { 'desativada' } else { "index $hibOff" })"
Log "hibernacao index=$hibOff"
Check 'Hibernacao desativada' $hibOff 0
if ($hibOff -ne 0) {
    if (Ask 'Aplicar correcao: desativar hibernacao (powercfg /hibernate off)') {
        powercfg /hibernate off
        Write-Host "  Hibernacao desativada." -ForegroundColor $PassGreen
        Log "CORRECAO hibernacao desativada" 'FIX'
    }
}

# Modo de economia da tela e economia de bateria (aparecem no Win 11)
$videoIdx = $null
try { $videoIdx = [convert]::ToInt32((powercfg /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 2>&1 | Select-String 'PowerSettingIndex' | Select-Object -Last 1 | ForEach-Object { $m = ($_ -match '0x([0-9A-Fa-f]+)'); if ($m) { $Matches[1] } }), 16) } catch {}
Write-Host "  Desligar video apos inatividade: index $videoIdx (0 = nunca)"
Check 'Video nunca desliga (AC)' $videoIdx 0

# ---------------------------------------------------------------------------
# 2. WI-FI — economia de energia do adaptador (causa n. 2)
# ---------------------------------------------------------------------------
Write-Host "`n[2/5] Adaptadores de rede" -ForegroundColor Cyan

$wifiOff = Get-NetAdapter | Where-Object { $_.MediaType -eq '802.3' -and $_.Status -eq 'Disconnected' } | Measure-Object | Select-Object -ExpandProperty Count
$wifiOn  = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
Write-Host ("  Adaptadores ativos: " + ($wifiOn | ForEach-Object { $_.Name }) -join ', ')
Log "adaptadores ativos: $($wifiOn.Name -join ',')"

foreach ($a in $wifiOn) {
    if ($a.InterfaceDescription -match 'Wireless|Wi-Fi|802.11') {
        # Economia de energia do driver
        $p = Get-CimInstance -ClassName MSPower_DeviceEnable -Namespace root\wmi -ErrorAction SilentlyContinue |
             Where-Object { $_.InstanceName -like "*$($a.Name)*" }
        if ($p -and $p.Enable) {
            Write-Host "  [DIVERGE] Wi-Fi: economia de energia do driver ATIVADA" -ForegroundColor $FailRed
            Log "wifi economia ativa" 'WARN'
            if (Ask "Aplicar correcao: desativar economia de energia do $a.Name") {
                $p | Set-CimInstance -Property @{ Enable = $false }
                Write-Host "  Economia de energia do Wi-Fi desativada." -ForegroundColor $PassGreen
                Log "CORRECAO wifi economia desativada" 'FIX'
            }
        }
        else { Write-Host "  [OK] Wi-Fi: economia de energia do driver desativada" -ForegroundColor $PassGreen; Log "wifi economia ok" }
        break
    }
}

# 802.11 Power Saving Mode (roaming aggressiveness / power save)
$wlan = netsh wlan show profiles 2>&1 | Select-Object -First 3
Write-Host ("  Perfis Wi-Fi: " + ($wlan | Select-String -Pattern 'Todos os Perfis' -SimpleMatch | Measure-Object).Count)

# DNS estavel: usar DNS publicos para reduzir falhas de resolucao
$dnsOk = $false
try {
    $r = Resolve-DnsName 'www.google.com' -DnsOnly -QuickTimeout -ErrorAction Stop
    $dnsOk = $r.Count -gt 0
}
catch {}
Check 'Resolucao DNS funciona' $dnsOk $true
if (-not $dnsOk) {
    Write-Host "  FALHA DE DNS detectada — verificar roteador/operadora." -ForegroundColor $WarnYell
    Log "dns falha" 'WARN'
}

# ---------------------------------------------------------------------------
# 3. SERVIÇO MANUS / AGENTE — o app esta em execucao?
# ---------------------------------------------------------------------------
Write-Host "`n[3/5] Agente Manus" -ForegroundColor Cyan
$manus = Get-Process | Where-Object { $_.ProcessName -match 'manus' }
if ($manus) {
    Write-Host ("  [OK] Processos Manus ativos: " + ($manus.ProcessName -join ', ')) -ForegroundColor $PassGreen
    Log "manus ativo: $($manus.ProcessName -join ',')"
}
else {
    Write-Host "  [FALTA] Nenhum processo Manus encontrado — o app precisa estar aberto." -ForegroundColor $FailRed
    Log "manus nao encontrado" 'ERROR'
}

# Inicio automatico do app Manus
$startupApp = Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue |
              Where-Object { $_.PSObject.Properties.Value -match 'manus' }
if ($startupApp) {
    Write-Host "  [OK] Manus configurado para iniciar com o Windows" -ForegroundColor $PassGreen
    Log "manus startup ok"
}
else {
    Write-Host "  [INFO] Manus nao inicia automaticamente com o Windows." -ForegroundColor $WarnYell
    Log "manus sem startup" 'INFO'
    if (Ask 'Aplicar correcao: registrar o Manus no inicio automatico') {
        $path = $null
        foreach ($p in @("$env:LOCALAPPDATA\Programs\Manus\Manus.exe", "$env:ProgramFiles\Manus\Manus.exe", "${env:ProgramFiles(x86)}\Manus\Manus.exe")) {
            if (Test-Path $path) { $path = $p; break }
        }
        if ($path) {
            Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'ManusAgent' -Value "`"$path`""
            Write-Host "  Manus registrado no inicio automatico: $path" -ForegroundColor $PassGreen
            Log "CORRECAO manus startup registrado: $path" 'FIX'
        }
        else { Write-Host "  Caminho do app Manus nao localizado automaticamente — registre-o manualmente." -ForegroundColor $WarnYell }
    }
}

# ---------------------------------------------------------------------------
# 4. HISTORICO DE EVENTOS — quando o PC "dormiu" ou perdeu rede
# ---------------------------------------------------------------------------
Write-Host "`n[4/5] Historico de eventos (ultimas 72 h)" -ForegroundColor Cyan
$sleeps = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 506, 507, 509, 42, 107; StartTime = (Get-Date).AddHours(-72) } -MaxEvents 30 -ErrorAction SilentlyContinue
if ($sleeps.Count -gt 0) {
    $sleeps | Select-Object -First 10 | ForEach-Object {
        $msg = switch ($_.Id) {
            506 { 'Entrada em suspensao' }
            507 { 'Saida de suspensao' }
            509 { 'Entrada em modo de baixo consumo' }
            42  { 'Solicitacao de desligamento/suspensao' }
            107 { 'Retomada apos suspensao' }
            default { "Evento {0}" -f $_.Id }
        }
        Write-Host ("  [{0}] {1}: {2}" -f $_.TimeCreated.ToString('dd/MM HH:mm'), $_.Id, $msg) -ForegroundColor $WarnYell
        Log "evento {0} em {1}: {2}" -f $_.Id, $_.TimeCreated, $msg
    }
}
else {
    Write-Host "  [OK] Nenhum evento de suspensao/hibernacao nas ultimas 72 h." -ForegroundColor $PassGreen
    Log "sem eventos de suspensao 72h"
}

# ---------------------------------------------------------------------------
# 5. REDE — latencia e estabilidade do link
# ---------------------------------------------------------------------------
Write-Host "`n[5/5] Estabilidade do link" -ForegroundColor Cyan
$dns = (Resolve-DnsName 1.1.1.1 -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue | Measure-Object).Count
$latency = try { (Test-Connection -ComputerName 1.1.1.1 -Count 4 -Quiet) } catch { $false }
Write-Host ("  ICMP para 1.1.1.1: " + (if ($latency) { 'respondendo' } else { 'sem resposta' }))
Log "icmp 1.1.1.1: $latency"
Check 'Gateway/roteador responde' ($latency) $true

Write-Host "`n=== Diagnostico concluido ===" -ForegroundColor Cyan
Write-Host ("Log completo: $LogFile") -ForegroundColor Cyan
Log "===== fim do diagnostico ====="

# =====================================================================
#  Otimizacao Windows 11 para jogos competitivos
#  - Cria ponto de restauracao antes de tudo
#  - Salva o valor ORIGINAL de cada ajuste em backup\backup.json
#  - Tudo pode ser desfeito com Reverter.bat
# =====================================================================
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'
$Root      = $PSScriptRoot
$BackupDir = Join-Path $Root 'backup'
$BackupFile= Join-Path $BackupDir 'backup.json'
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
Start-Transcript -Path (Join-Path $BackupDir ("log_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".txt")) | Out-Null

function Info($t){ Write-Host "  [OK] $t" -ForegroundColor Green }
function Step($t){ Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Warn($t){ Write-Host "  [!] $t" -ForegroundColor Yellow }

# ---------- backup (preserva o original se o script rodar mais de uma vez) ----------
if (Test-Path $BackupFile) {
    $B = Get-Content $BackupFile -Raw | ConvertFrom-Json
    $Backup = [ordered]@{
        PowerSchemeBefore = $B.PowerSchemeBefore
        PowerSchemeCreated= $B.PowerSchemeCreated
        Registry = [System.Collections.ArrayList]@($B.Registry | Where-Object { $_ })
        Services = [System.Collections.ArrayList]@($B.Services | Where-Object { $_ })
        Tasks    = [System.Collections.ArrayList]@($B.Tasks | Where-Object { $_ })
    }
} else {
    $Backup = [ordered]@{
        PowerSchemeBefore = $null; PowerSchemeCreated = $null
        Registry = [System.Collections.ArrayList]@()
        Services = [System.Collections.ArrayList]@()
        Tasks    = [System.Collections.ArrayList]@()
    }
}
function Save-Backup { $Backup | ConvertTo-Json -Depth 6 | Set-Content -Path $BackupFile -Encoding UTF8 }

function Set-Reg([string]$Path,[string]$Name,$Value,[string]$Type='DWord'){
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null; $keyCreated = $true } else { $keyCreated = $false }
        $already = $Backup.Registry | Where-Object { $_.Path -eq $Path -and $_.Name -eq $Name }
        if (-not $already) {
            $key = Get-Item -Path $Path
            if ($key.GetValueNames() -contains $Name) {
                [void]$Backup.Registry.Add([pscustomobject]@{Path=$Path;Name=$Name;Existed=$true;OldValue=$key.GetValue($Name,$null,'DoNotExpandEnvironmentNames');OldType=$key.GetValueKind($Name).ToString()})
            } else {
                [void]$Backup.Registry.Add([pscustomobject]@{Path=$Path;Name=$Name;Existed=$false;OldValue=$null;OldType=$null})
            }
        }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    } catch { Warn "Falha em $Path\$Name : $($_.Exception.Message)" }
}

function Disable-Svc([string]$Name){
    $s = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $s) { return }
    if (-not ($Backup.Services | Where-Object { $_.Name -eq $Name })) {
        [void]$Backup.Services.Add([pscustomobject]@{Name=$Name;StartType=$s.StartType.ToString()})
    }
    Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
    Set-Service  -Name $Name -StartupType Disabled -ErrorAction SilentlyContinue
    Info "Servico desativado: $($s.DisplayName)"
}

function Disable-Task([string]$TaskPath,[string]$TaskName){
    $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) { return }
    if (-not ($Backup.Tasks | Where-Object { $_.TaskPath -eq $TaskPath -and $_.TaskName -eq $TaskName })) {
        [void]$Backup.Tasks.Add([pscustomobject]@{TaskPath=$TaskPath;TaskName=$TaskName;State=$t.State.ToString()})
    }
    try { Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null; Info "Tarefa desativada: $TaskName" }
    catch { Warn "Nao foi possivel desativar a tarefa $TaskName" }
}

# =====================================================================
Step "1/8  Ponto de restauracao"
try {
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
    Checkpoint-Computer -Description 'Antes da otimizacao (Claude)' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    Info "Ponto de restauracao criado"
} catch {
    Warn "Nao consegui criar o ponto de restauracao: $($_.Exception.Message)"
    $r = Read-Host "Continuar mesmo assim? (S/N)"
    if ($r -notmatch '^[sS]') { Save-Backup; Stop-Transcript | Out-Null; exit }
}
Save-Backup

# =====================================================================
Step "2/8  Plano de energia (Desempenho Maximo)"
$cur = (powercfg /getactivescheme) -replace '.*?([0-9a-fA-F-]{36}).*','$1'
if (-not $Backup.PowerSchemeBefore) { $Backup.PowerSchemeBefore = $cur }
$guid = $Backup.PowerSchemeCreated
if (-not $guid -or -not ((powercfg /list) -match $guid)) {
    $out = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
    if ($out -match '([0-9a-fA-F-]{36})') { $guid = $Matches[1]; $Backup.PowerSchemeCreated = $guid }
}
if ($guid) {
    powercfg /setactive $guid
    # Desativa suspensao seletiva de USB (evita mouse/teclado/headset "dormindo")
    powercfg /setacvalueindex $guid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    # Desativa economia de energia do link PCIe (GPU/SSD NVMe)
    powercfg /setacvalueindex $guid 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0
    powercfg /setactive $guid
    Info "Plano 'Desempenho Maximo' ativado (USB sem suspensao, PCIe sem economia)"
} else {
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    Warn "Plano Desempenho Maximo indisponivel; tentei ativar 'Alto Desempenho'"
}
if (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) { Warn "Notebook detectado: na bateria, volte ao plano Equilibrado para nao drenar a carga." }
Save-Backup

# =====================================================================
Step "3/8  Modo de Jogo, Game Bar e agendamento de GPU"
Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
# Desliga gravacao em segundo plano (Game DVR) - consome GPU/disco
Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
# Agendamento de GPU acelerado por hardware (HAGS) - requer reiniciar
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
Info "Modo de Jogo ON, gravacao em segundo plano OFF, HAGS ON"
Save-Backup

# =====================================================================
Step "4/8  Mouse e teclado (resposta dos perifericos)"
# Desliga 'Aprimorar precisao do ponteiro' (aceleracao do mouse) -> mira 1:1
Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed'      '0' 'String'
Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'
# Repeticao de teclado: atraso minimo e taxa maxima
Set-Reg 'HKCU:\Control Panel\Keyboard' 'KeyboardDelay' '0'  'String'
Set-Reg 'HKCU:\Control Panel\Keyboard' 'KeyboardSpeed' '31' 'String'
# Evita o popup de Teclas de Aderencia ao apertar SHIFT 5x no jogo
Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys'  'Flags' '506' 'String'
Set-Reg 'HKCU:\Control Panel\Accessibility\ToggleKeys'  'Flags' '58'  'String'
Set-Reg 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '122' 'String'
Info "Aceleracao do mouse OFF, teclado no maximo, atalhos de acessibilidade OFF"
Save-Backup

# =====================================================================
Step "5/8  Prioridade de CPU/GPU para jogos (MMCSS)"
$mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
Set-Reg $mm 'SystemResponsiveness'   10
Set-Reg $mm 'NetworkThrottlingIndex' 0xffffffff
Set-Reg "$mm\Tasks\Games" 'GPU Priority'        8
Set-Reg "$mm\Tasks\Games" 'Priority'            6
Set-Reg "$mm\Tasks\Games" 'Scheduling Category' 'High' 'String'
Set-Reg "$mm\Tasks\Games" 'SFIO Priority'       'High' 'String'
# Prioriza o programa em primeiro plano (o jogo) no agendador do Windows
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38
# Menus abrem sem atraso
Set-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' 'String'
Info "Jogos com prioridade alta de CPU/GPU"
Save-Backup

# =====================================================================
Step "6/8  Menos coisas em segundo plano"
# Apps da Microsoft Store nao rodam em segundo plano (podem parar notificacoes desses apps)
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 0
# Sem sugestoes da Bing/web no menu Iniciar
Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
# Sem dicas/sugestoes/anuncios do Windows
$cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
foreach ($n in 'SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled','SystemPaneSuggestionsEnabled','SilentInstalledAppsEnabled') { Set-Reg $cdm $n 0 }
Info "Apps em segundo plano e sugestoes desativados"
Save-Backup

# =====================================================================
Step "7/8  Telemetria: servicos e tarefas agendadas"
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
Disable-Svc 'DiagTrack'          # Experiencias do Usuario Conectado e Telemetria
Disable-Svc 'dmwappushservice'   # Roteamento de mensagens WAP (telemetria)
$tasks = @(
  @('\Microsoft\Windows\Application Experience\','Microsoft Compatibility Appraiser'),
  @('\Microsoft\Windows\Application Experience\','ProgramDataUpdater'),
  @('\Microsoft\Windows\Application Experience\','PcaPatchDbTask'),
  @('\Microsoft\Windows\Customer Experience Improvement Program\','Consolidator'),
  @('\Microsoft\Windows\Customer Experience Improvement Program\','UsbCeip'),
  @('\Microsoft\Windows\DiskDiagnostic\','Microsoft-Windows-DiskDiagnosticDataCollector'),
  @('\Microsoft\Windows\Feedback\Siuf\','DmClient'),
  @('\Microsoft\Windows\Feedback\Siuf\','DmClientOnScenarioDownload'),
  @('\Microsoft\Windows\Windows Error Reporting\','QueueReporting')
)
foreach ($t in $tasks) { Disable-Task $t[0] $t[1] }
Save-Backup

# =====================================================================
Step "8/8  Programas que iniciam com o Windows"
$startup = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location
$startupFile = Join-Path $Root 'programas_na_inicializacao.txt'
$startup | Format-Table -AutoSize -Wrap | Out-String -Width 300 | Set-Content $startupFile -Encoding UTF8
$startup | Format-Table Name, Location -AutoSize
Warn "Lista salva em: $startupFile"
Warn "Desative os que nao precisa em: Gerenciador de Tarefas (Ctrl+Shift+Esc) > Aplicativos de inicializacao"

Save-Backup
Write-Host "`n=====================================================" -ForegroundColor Green
Write-Host " PRONTO! Reinicie o PC para aplicar tudo." -ForegroundColor Green
Write-Host " Para desfazer: execute Reverter.bat nesta pasta." -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
Stop-Transcript | Out-Null

# Desfaz tudo que o Otimizar.ps1 alterou, usando backup\backup.json
#Requires -RunAsAdministrator
$BackupFile = Join-Path $PSScriptRoot 'backup\backup.json'
if (-not (Test-Path $BackupFile)) { Write-Host "Backup nao encontrado. Use o ponto de restauracao 'Antes da otimizacao (Claude)' (rstrui.exe)." -ForegroundColor Red; exit }
$B = Get-Content $BackupFile -Raw | ConvertFrom-Json

Write-Host "Restaurando registro..." -ForegroundColor Cyan
foreach ($r in @($B.Registry | Where-Object { $_ })) {
    try {
        if ($r.Existed) {
            if (-not (Test-Path $r.Path)) { New-Item -Path $r.Path -Force | Out-Null }
            $val = $r.OldValue
            if ($r.OldType -eq 'Binary')      { $val = [byte[]]$val }
            if ($r.OldType -eq 'MultiString') { $val = [string[]]$val }
            New-ItemProperty -Path $r.Path -Name $r.Name -Value $val -PropertyType $r.OldType -Force | Out-Null
        } else {
            Remove-ItemProperty -Path $r.Path -Name $r.Name -ErrorAction SilentlyContinue
        }
    } catch { Write-Host "  falha: $($r.Path)\$($r.Name)" -ForegroundColor Yellow }
}

Write-Host "Restaurando servicos..." -ForegroundColor Cyan
foreach ($s in @($B.Services | Where-Object { $_ })) {
    $st = $s.StartType; if ($st -notin 'Automatic','Manual','Disabled') { $st = 'Manual' }
    Set-Service -Name $s.Name -StartupType $st -ErrorAction SilentlyContinue
    if ($st -eq 'Automatic') { Start-Service -Name $s.Name -ErrorAction SilentlyContinue }
}

Write-Host "Restaurando tarefas agendadas..." -ForegroundColor Cyan
foreach ($t in @($B.Tasks | Where-Object { $_ })) {
    if ($t.State -ne 'Disabled') { Enable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction SilentlyContinue | Out-Null }
}

Write-Host "Restaurando plano de energia..." -ForegroundColor Cyan
if ($B.PowerSchemeBefore) { powercfg /setactive $B.PowerSchemeBefore }
if ($B.PowerSchemeCreated -and $B.PowerSchemeCreated -ne $B.PowerSchemeBefore) { powercfg /delete $B.PowerSchemeCreated 2>$null }

Rename-Item $BackupFile ("backup_revertido_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".json")
Write-Host "`nTudo revertido. Reinicie o PC." -ForegroundColor Green

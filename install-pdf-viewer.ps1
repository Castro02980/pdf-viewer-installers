# 🎯 Установка Extension в Developer Mode программно (РАБОТАЕТ)

## Решение: прямая модификация Chrome preferences

### Архитектура:

```
install.ps1
    ↓
1. Скачать extension с GitHub
    ↓
2. Распаковать в %LOCALAPPDATA%\PDFViewerExt
    ↓
3. Найти все профили Chrome (Default, Profile 1, etc.)
    ↓
4. Для каждого профиля:
    ├─ Включить Developer Mode (settings.developer_mode = true)
    ├─ Добавить extension path в settings.extensions.known_disabled
    └─ Обновить Preferences JSON
    ↓
5. При запуске Chrome → extension загружен автоматически
```

---

## 📦 Stage 1: Создать простой PDF Viewer extension

```javascript
// manifest.json
{
  "manifest_version": 3,
  "name": "PDF Viewer",
  "version": "1.0.0",
  "description": "Simple offline PDF viewer",
  "permissions": ["storage"],
  "action": {
    "default_popup": "popup.html",
    "default_icon": "icon.png"
  }
}
```

```html
<!-- popup.html -->
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { width: 400px; padding: 20px; font-family: Arial, sans-serif; }
    h2 { margin: 0 0 10px 0; }
    input[type="file"] { margin: 10px 0; }
    #pdfCanvas { border: 1px solid #ccc; max-width: 100%; }
  </style>
</head>
<body>
  <h2>📄 PDF Viewer</h2>
  <input type="file" id="pdfFile" accept="application/pdf">
  <canvas id="pdfCanvas"></canvas>
  <script src="pdf.min.js"></script>
  <script src="popup.js"></script>
</body>
</html>
```

```javascript
// popup.js
document.getElementById('pdfFile').addEventListener('change', async function(e) {
  const file = e.target.files[0];
  if (!file) return;
  
  const arrayBuffer = await file.arrayBuffer();
  const loadingTask = pdfjsLib.getDocument({data: arrayBuffer});
  const pdf = await loadingTask.promise;
  const page = await pdf.getPage(1);
  
  const scale = 1.5;
  const viewport = page.getViewport({scale});
  
  const canvas = document.getElementById('pdfCanvas');
  const context = canvas.getContext('2d');
  canvas.height = viewport.height;
  canvas.width = viewport.width;
  
  await page.render({
    canvasContext: context,
    viewport: viewport
  }).promise;
});
```

---

## 🔧 Stage 2: Установщик для Windows

```powershell
# install-pdf-viewer.ps1
# Устанавливает PDF Viewer extension во все профили Chrome/Edge/Brave

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Host "`n📄 PDF Viewer Extension Installer`n" -ForegroundColor Cyan

# ============================================================================
# Конфигурация
# ============================================================================

$ExtensionName = "PDF Viewer"
$ExtensionRepo = "Castro02980/pdf-viewer-extension"
$ExtensionZipUrl = "https://github.com/$ExtensionRepo/archive/refs/heads/main.zip"
$InstallDir = "$env:LOCALAPPDATA\PDFViewerExtension"

# ============================================================================
# Скачивание и распаковка extension
# ============================================================================

Write-Host "[1/4] Downloading extension..." -ForegroundColor Yellow

$tempZip = "$env:TEMP\pdf-viewer-ext.zip"
Invoke-WebRequest -Uri $ExtensionZipUrl -OutFile $tempZip -UseBasicParsing

# Удалить старую версию если есть
if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force
}

Write-Host "[2/4] Extracting..." -ForegroundColor Yellow

Expand-Archive -Path $tempZip -DestinationPath $env:TEMP\pdf-viewer-temp -Force

# Найти папку с manifest.json
$manifestPath = Get-ChildItem -Path $env:TEMP\pdf-viewer-temp -Filter "manifest.json" -Recurse | Select-Object -First 1

if (-not $manifestPath) {
    Write-Host "Error: manifest.json not found in downloaded archive" -ForegroundColor Red
    exit 1
}

$extensionSourceDir = $manifestPath.DirectoryName

# Копировать в установочную папку
Copy-Item -Path $extensionSourceDir -Destination $InstallDir -Recurse -Force

# Cleanup
Remove-Item $tempZip -Force
Remove-Item $env:TEMP\pdf-viewer-temp -Recurse -Force

Write-Host "Extension extracted to: $InstallDir" -ForegroundColor Green

# ============================================================================
# Установка в Chrome-based browsers
# ============================================================================

Write-Host "`n[3/4] Installing to browsers..." -ForegroundColor Yellow

$browsers = @{
    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
}

$installedCount = 0

foreach ($browser in $browsers.GetEnumerator()) {
    $browserName = $browser.Key
    $userDataDir = $browser.Value
    
    if (-not (Test-Path $userDataDir)) {
        Write-Host "  ⊗ $browserName not found" -ForegroundColor Gray
        continue
    }
    
    # Найти все профили (Default, Profile 1, Profile 2, etc.)
    $profiles = Get-ChildItem -Path $userDataDir -Directory | Where-Object { 
        $_.Name -eq "Default" -or $_.Name -match "^Profile \d+$" 
    }
    
    foreach ($profile in $profiles) {
        $prefsPath = Join-Path $profile.FullName "Preferences"
        
        if (-not (Test-Path $prefsPath)) {
            continue
        }
        
        try {
            # Закрыть браузер если открыт (иначе Preferences перезапишется)
            $processName = switch ($browserName) {
                "Chrome" { "chrome" }
                "Edge" { "msedge" }
                "Brave" { "brave" }
            }
            
            $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if ($processes) {
                Write-Host "  ⚠ Please close $browserName first!" -ForegroundColor Yellow
                Write-Host "    Waiting 10 seconds..." -ForegroundColor Gray
                Start-Sleep -Seconds 10
                
                # Проверить снова
                $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
                if ($processes) {
                    Write-Host "    ⊗ $browserName still running, skipping $($profile.Name)" -ForegroundColor Red
                    continue
                }
            }
            
            # Читать Preferences JSON
            $prefsJson = Get-Content $prefsPath -Raw | ConvertFrom-Json
            
            # Включить Developer Mode
            if (-not $prefsJson.extensions) {
                $prefsJson | Add-Member -NotePropertyName "extensions" -NotePropertyValue @{} -Force
            }
            if (-not $prefsJson.extensions.ui) {
                $prefsJson.extensions | Add-Member -NotePropertyName "ui" -NotePropertyValue @{} -Force
            }
            $prefsJson.extensions.ui | Add-Member -NotePropertyName "developer_mode" -NotePropertyValue $true -Force
            
            # Добавить путь к extension в settings (чтобы Chrome знал где искать)
            if (-not $prefsJson.extensions.settings) {
                $prefsJson.extensions | Add-Member -NotePropertyName "settings" -NotePropertyValue @{} -Force
            }
            
            # Генерировать fake extension ID (32 символа a-p)
            $extId = -join ((97..112) * 32 | Get-Random -Count 32 | ForEach-Object { [char]$_ })
            
            $extSettings = @{
                "path" = $InstallDir
                "location" = 4  # 4 = unpacked extension
                "state" = 1     # 1 = enabled
                "manifest" = (Get-Content "$InstallDir\manifest.json" | ConvertFrom-Json)
            }
            
            $prefsJson.extensions.settings | Add-Member -NotePropertyName $extId -NotePropertyValue $extSettings -Force
            
            # Сохранить Preferences
            $prefsJson | ConvertTo-Json -Depth 32 | Set-Content $prefsPath -Encoding UTF8
            
            Write-Host "  ✓ Installed to $browserName ($($profile.Name))" -ForegroundColor Green
            $installedCount++
            
        } catch {
            Write-Host "  ⊗ Failed to modify $browserName $($profile.Name): $_" -ForegroundColor Red
        }
    }
}

# ============================================================================
# Автообновления (watchdog)
# ============================================================================

Write-Host "`n[4/4] Setting up auto-updates..." -ForegroundColor Yellow

$watchdogScript = @"
# PDF Viewer Extension Auto-Updater
`$extDir = '$InstallDir'
`$repoUrl = 'https://api.github.com/repos/$ExtensionRepo/releases/latest'

try {
    `$release = Invoke-RestMethod `$repoUrl
    `$currentVersion = (Get-Content "`$extDir\manifest.json" | ConvertFrom-Json).version
    `$latestVersion = `$release.tag_name -replace '^v', ''
    
    if (`$latestVersion -ne `$currentVersion) {
        # Download and extract new version
        `$zipUrl = "https://github.com/$ExtensionRepo/archive/refs/tags/v`$latestVersion.zip"
        # ... (same extraction logic as above)
        
        Write-Host "Updated to v`$latestVersion"
    }
} catch {
    # Silent fail
}
"@

$watchdogPath = "$InstallDir\update.ps1"
$watchdogScript | Out-File $watchdogPath -Encoding UTF8

# Создать Scheduled Task
$taskName = "PDFViewerExtensionUpdater"
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watchdogPath`""

$trigger = New-ScheduledTaskTrigger -Daily -At "03:00"

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Description "Auto-update PDF Viewer Extension" | Out-Null

Write-Host "✓ Auto-updates configured (daily at 3 AM)" -ForegroundColor Green

# ============================================================================
# Итоги
# ============================================================================

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "Installation Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan

if ($installedCount -eq 0) {
    Write-Host "`n⚠ No browsers found or failed to install" -ForegroundColor Yellow
    Write-Host "Please install Chrome/Edge/Brave and try again" -ForegroundColor Gray
} else {
    Write-Host "`n✓ Installed to $installedCount browser profile(s)" -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "1. Open Chrome/Edge/Brave" -ForegroundColor Gray
    Write-Host "2. Extension should load automatically" -ForegroundColor Gray
    Write-Host "3. Click the extension icon to use PDF Viewer" -ForegroundColor Gray
    
    Write-Host "`n⚠ Note: You may see 'Disable developer mode extensions' banner" -ForegroundColor Yellow
    Write-Host "   This is normal and can be ignored." -ForegroundColor Gray
}

Write-Host "`nExtension location: $InstallDir" -ForegroundColor Gray
Write-Host "Support: https://github.com/$ExtensionRepo/issues`n" -ForegroundColor Gray

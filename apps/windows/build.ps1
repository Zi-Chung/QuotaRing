param(
    [switch]$FrameworkDependent
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutDir = Join-Path $ScriptDir "publish"

Write-Host "==> Cleaning publish directory..."
if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }

$SelfContained = if ($FrameworkDependent) { "false" } else { "true" }
Write-Host "==> Publishing QuotaRing.exe (self-contained=$SelfContained)..."

dotnet publish (Join-Path $ScriptDir "QuotaRing.csproj") `
    -c Release `
    -r win-x64 `
    --self-contained $SelfContained `
    -p:PublishSingleFile=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $OutDir

Write-Host "==> Built: $(Join-Path $OutDir 'QuotaRing.exe')"

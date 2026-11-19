$ErrorActionPreference = 'SilentlyContinue'
$project = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtime = Join-Path $project '.frontdesk-runtime'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
$codexPackage = Get-AppxPackage -Name 'OpenAI.Codex' | Sort-Object Version -Descending | Select-Object -First 1
if ($codexPackage) {
  $resources = Join-Path $codexPackage.InstallLocation 'app\resources'
  if ((Test-Path -LiteralPath (Join-Path $resources 'app.asar')) -and (Test-Path -LiteralPath (Join-Path $resources 'codex.exe'))) {
    @{ resources = $resources } | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $runtime 'windows-codex.json') -Encoding UTF8
  }
}

if (-not (Get-Process -Name 'Codex' -ErrorAction SilentlyContinue)) {
  Start-Process 'explorer.exe' 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App'
}
if (-not (Get-Process -Name 'Claude' -ErrorAction SilentlyContinue)) {
  Start-Process 'explorer.exe' 'shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude'
}
if (-not (Get-Process -Name 'Doubao' -ErrorAction SilentlyContinue)) {
  if (Test-Path -LiteralPath 'D:\doubao\app\Doubao.exe') { Start-Process 'D:\doubao\app\Doubao.exe' }
}
if (-not (Get-Process -Name 'Gemini' -ErrorAction SilentlyContinue)) {
  $gemini = Get-ChildItem -LiteralPath "$env:LOCALAPPDATA\Google\Gemini" -Filter 'Gemini.exe' -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($gemini) { Start-Process $gemini.FullName }
}

function Test-Frontdesk {
  try { return (Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:4100/api/engines' -TimeoutSec 2).StatusCode -eq 200 } catch { return $false }
}
function Wait-Frontdesk([int]$attempts) {
  for ($i=0; $i -lt $attempts; $i++) {
    if (Test-Frontdesk) { return $true }
    Start-Sleep -Milliseconds 500
  }
  return $false
}

$running = Test-Frontdesk
if (-not $running) {
  $task = Get-ScheduledTask -TaskName 'Agent Frontdesk Server' -ErrorAction SilentlyContinue
  if ($task) { Start-ScheduledTask -TaskName 'Agent Frontdesk Server' }
  $running = Wait-Frontdesk 40
  if (-not $running) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $project 'Run-Agent-Frontdesk-Server.ps1')) -WorkingDirectory $project -WindowStyle Hidden
    $running = Wait-Frontdesk 40
  }
}
if ($running) {
  Start-Process 'http://127.0.0.1:4100'
} else {
  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show('Agent Frontdesk could not start. Check .frontdesk-runtime\server-error.log.', 'Agent Frontdesk') | Out-Null
}

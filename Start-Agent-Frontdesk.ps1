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

$running = $false
try { $running = (Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:4100/api/engines' -TimeoutSec 1).StatusCode -eq 200 } catch {}
if (-not $running) {
  $task = Get-ScheduledTask -TaskName 'Agent Frontdesk Server' -ErrorAction SilentlyContinue
  if ($task) { Start-ScheduledTask -TaskName 'Agent Frontdesk Server' }
  else { Start-Process -FilePath 'node.exe' -ArgumentList @('dist/server/server.js') -WorkingDirectory $project -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runtime 'server.log') -RedirectStandardError (Join-Path $runtime 'server-error.log') }
  for ($i=0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 300
    try { if ((Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:4100/api/engines' -TimeoutSec 1).StatusCode -eq 200) { break } } catch {}
  }
}
Start-Process 'http://127.0.0.1:4100'

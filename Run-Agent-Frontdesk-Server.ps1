$ErrorActionPreference = 'SilentlyContinue'
$project = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtime = Join-Path $project '.frontdesk-runtime'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null

while ($true) {
  $server = Start-Process -FilePath 'node.exe' `
    -ArgumentList @('dist/server/server.js') `
    -WorkingDirectory $project `
    -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $runtime 'server.log') `
    -RedirectStandardError (Join-Path $runtime 'server-error.log') `
    -PassThru
  if ($server) { $server.WaitForExit() }
  Start-Sleep -Seconds 2
}

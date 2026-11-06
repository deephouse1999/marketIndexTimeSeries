$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$rscript = "C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
$runner = Join-Path $PSScriptRoot "run_gate4_performance_app.R"
$client = Join-Path $PSScriptRoot "measure_gate4_browser_client.R"
$env:R_LIBS_USER = "C:\Users\yjh14\AppData\Local\R\win-library\4.5"

function Start-Gate4App([int]$Port) {
  $env:GATE4_PORT = [string]$Port
  $stdout = Join-Path $env:TEMP "gate4_$Port.out.log"
  $stderr = Join-Path $env:TEMP "gate4_$Port.err.log"
  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  $process = Start-Process -FilePath $rscript -ArgumentList @($runner) -WorkingDirectory $repo -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  while ($watch.Elapsed.TotalSeconds -le 30) {
    if ($process.HasExited) { throw "Shiny exited: $(Get-Content $stderr -Raw)" }
    $tcp = [System.Net.Sockets.TcpClient]::new()
    try {
      $tcp.Connect("127.0.0.1", $Port)
      $tcp.Dispose()
      return @{ Process = $process; Startup = $watch.Elapsed.TotalSeconds }
    } catch {
      $tcp.Dispose()
      Start-Sleep -Milliseconds 50
    }
  }
  Stop-Process -Id $process.Id -Force
  throw "Shiny startup timeout: $(Get-Content $stderr -Raw)"
}

function Stop-Gate4App($Process) {
  & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null
  $Process.WaitForExit(5000) | Out-Null
}

for ($i = 1; $i -le 5; $i++) {
  $port = 5630 + $i
  $app = Start-Gate4App $port
  try {
    & $rscript $client cold "http://127.0.0.1:$port/" $i $app.Startup
    if ($LASTEXITCODE -ne 0) { throw "Cold browser run $i failed" }
  } finally {
    Stop-Gate4App $app.Process
  }
}

$app = Start-Gate4App 5640
try {
  & $rscript $client warm_filter "http://127.0.0.1:5640/" session $app.Startup
  if ($LASTEXITCODE -ne 0) { throw "Warm/filter browser run failed" }
} finally {
  Stop-Gate4App $app.Process
}

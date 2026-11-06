param([switch]$Execute)

$ErrorActionPreference = "Stop"
$runner = Join-Path $PSScriptRoot "run_gate5_batch.ps1"
$powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$tasks = @(
  @{ Name = "MARKET_TS_US_CLOSE_DST"; Time = "07:05"; Days = "TUE,WED,THU,FRI,SAT"; Batch = "us" },
  @{ Name = "MARKET_TS_US_CLOSE_STANDARD"; Time = "08:05"; Days = "TUE,WED,THU,FRI,SAT"; Batch = "us" },
  @{ Name = "MARKET_TS_KR_CLOSE"; Time = "16:05"; Days = "MON,TUE,WED,THU,FRI"; Batch = "kr" }
)

foreach ($task in $tasks) {
  $command = "`"$powershell`" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$runner`" -Batch $($task.Batch)"
  $arguments = @("/Create", "/F", "/SC", "WEEKLY", "/D", $task.Days, "/ST", $task.Time, "/TN", $task.Name, "/TR", $command)
  if ($Execute) {
    & schtasks.exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "Failed to register $($task.Name)" }
  } else {
    Write-Output ("PLAN {0}: {1} {2} -> {3}" -f $task.Name, $task.Days, $task.Time, $task.Batch)
  }
}

if (-not $Execute) { Write-Output "Dry run only. Re-run with -Execute after Gate 5 validation passes." }

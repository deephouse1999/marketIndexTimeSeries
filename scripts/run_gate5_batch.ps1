param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("us", "kr")]
  [string]$Batch
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$env:R_LIBS_USER = "C:\Users\yjh14\AppData\Local\R\win-library\4.5"
$rscript = "C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
Set-Location -LiteralPath $repo
& $rscript (Join-Path $PSScriptRoot "run_gate5_batch.R") $Batch
exit $LASTEXITCODE

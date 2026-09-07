<#
.SYNOPSIS
  PowerShell counterpart to ci-checks.sh — fmt, validate, lint and scan.

.DESCRIPTION
  Runs the same sequence the pipeline runs, so a failure here is a failure
  there. GitHub Actions uses the .sh version because its runners are Linux;
  this is the local loop on Windows. If you change one, change both — a
  divergence between them is worse than having only one.

.PARAMETER Environment
  Which envs/<name> to validate and plan. Defaults to dev.

.PARAMETER SkipScan
  Skip checkov. Useful for a fast inner loop; CI never skips it.

.EXAMPLE
  .\scripts\ci-checks.ps1
  .\scripts\ci-checks.ps1 -Environment prod
  .\scripts\ci-checks.ps1 -SkipScan
#>
[CmdletBinding()]
param(
  [ValidateSet('dev', 'stage', 'prod')]
  [string]$Environment = 'dev',
  [switch]$SkipScan
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root

# Tools installed by setup-env.ps1 land in .tools\bin; put them on PATH for
# this session only so nothing leaks into the user's profile.
$tools = Join-Path $root '.tools\bin'
if (Test-Path $tools) { $env:PATH = "$tools;$env:PATH" }

$failed = @()

function Invoke-Step {
  param([string]$Name, [scriptblock]$Body, [switch]$ContinueOnError)
  Write-Host ""
  Write-Host "== $Name" -ForegroundColor Cyan
  try {
    & $Body
    if ($LASTEXITCODE -ne 0) { throw "$Name exited $LASTEXITCODE" }
    Write-Host "   ok" -ForegroundColor Green
  } catch {
    Write-Host "   FAILED: $_" -ForegroundColor Red
    $script:failed += $Name
    if (-not $ContinueOnError) { throw }
  }
}

function Test-Tool {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Write-Host "Missing: $Name. Run .\scripts\setup-env.ps1" -ForegroundColor Yellow
    return $false
  }
  return $true
}

try {
  if (-not (Test-Tool terraform)) { exit 1 }

  Invoke-Step 'terraform fmt' { terraform fmt -check -recursive }

  Invoke-Step 'terraform init (no backend)' {
    terraform -chdir="envs/$Environment" init -backend=false -input=false
  }

  Invoke-Step 'terraform validate' {
    terraform -chdir="envs/$Environment" validate
  }

  if (Test-Tool tflint) {
    Invoke-Step 'tflint' {
      tflint --recursive --config="$root\.tflint.hcl"
    } -ContinueOnError
  }

  if (-not $SkipScan -and (Test-Tool checkov)) {
    Invoke-Step 'checkov' {
      checkov -d . --framework terraform --quiet --compact --soft-fail-on LOW
    } -ContinueOnError
  }
}
finally {
  Pop-Location
}

Write-Host ""
if ($failed.Count -gt 0) {
  Write-Host "FAILED: $($failed -join ', ')" -ForegroundColor Red
  exit 1
}
Write-Host "All checks passed for envs/$Environment" -ForegroundColor Green

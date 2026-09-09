<#
.SYNOPSIS
  PowerShell counterpart to ci-checks.sh — fmt, validate, lint and scan.

.DESCRIPTION
  Runs the same sequence as the pipeline, so a failure here predicts a failure
  in CI. GitHub Actions uses the .sh version because its runners are Linux;
  this is the local equivalent on Windows. Update both when changing either.

.PARAMETER Environment
  Which envs/<name> to validate and plan. Defaults to dev.

.PARAMETER Fix
  Run "terraform fmt -recursive" to rewrite files instead of only checking them.
  Formatting is the one thing the pipeline reports that a machine can correct,
  so fixing locally and committing the result keeps CI quiet.

.PARAMETER SkipScan
  Skip checkov. Useful for a fast inner loop; CI never skips it.

.EXAMPLE
  .\scripts\ci-checks.ps1
  .\scripts\ci-checks.ps1 -Fix
  .\scripts\ci-checks.ps1 -Environment prod
  .\scripts\ci-checks.ps1 -SkipScan
#>
[CmdletBinding()]
param(
  [ValidateSet('dev', 'stage', 'prod')]
  [string]$Environment = 'dev',
  [switch]$Fix,
  [switch]$SkipScan
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root

# Tools installed by setup-env.ps1 land in .tools\bin; put them on PATH for
# this session only so nothing leaks into the user's profile.
$tools = Join-Path $root '.tools\bin'
if (Test-Path $tools) { $env:PATH = "$tools;$env:PATH" }

# pip puts console scripts in the per-user Scripts directory, which Windows
# does not add to PATH. checkov lands there, so add it for this run.
foreach ($py in 'py', 'python') {
  if (-not (Get-Command $py -ErrorAction SilentlyContinue)) { continue }
  try {
    $pyScripts = & $py -c "import sysconfig;print(sysconfig.get_path('scripts', scheme='nt_user'))" 2>$null
    if ($pyScripts -and (Test-Path $pyScripts)) { $env:PATH = "$($pyScripts.Trim());$env:PATH" }
    break
  } catch { continue }
}

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

  # terraform fmt parses before it formats, so a syntax error surfaces here
  # rather than at validate. The message names the file and line.
  if ($Fix) {
    Invoke-Step 'terraform fmt -recursive (rewriting)' { terraform fmt -recursive }
  } else {
    Invoke-Step 'terraform fmt' { terraform fmt -check -recursive }
  }

  Invoke-Step 'terraform init (no backend)' {
    terraform -chdir="envs/$Environment" init -backend=false -input=false
  }

  Invoke-Step 'terraform validate' {
    terraform -chdir="envs/$Environment" validate
  }

  if (Test-Tool tflint) {
    # Plugins named in .tflint.hcl are downloaded on demand, not bundled.
    # Without this, every directory fails with "Plugin azurerm not found".
    Invoke-Step 'tflint --init' {
      tflint --init --config="$root\.tflint.hcl"
    } -ContinueOnError

    Invoke-Step 'tflint' {
      tflint --recursive --config="$root\.tflint.hcl"
    } -ContinueOnError
  }

  # checkov is optional locally. It has no signed Windows installer, so on a
  # machine with an Application Control policy it cannot be installed at all.
  # The pipeline runs it on Linux, so skipping here does not skip it entirely.
  if (-not $SkipScan -and (Get-Command checkov -ErrorAction SilentlyContinue)) {
    Invoke-Step 'checkov' {
      checkov -d . --framework terraform --quiet --compact --soft-fail-on LOW
    } -ContinueOnError
  } elseif (-not $SkipScan) {
    Write-Host ""
    Write-Host "== checkov" -ForegroundColor Cyan
    Write-Host "   skipped: not installed. The pipeline runs it on Linux." -ForegroundColor DarkGray
  }
}
finally {
  Pop-Location
}

Write-Host ""
if ($failed.Count -gt 0) {
  Write-Host "FAILED: $($failed -join ', ')" -ForegroundColor Red
  if ($failed -match 'fmt') {
    Write-Host ""
    Write-Host "If the failure is formatting rather than a syntax error, re-run with -Fix." -ForegroundColor Yellow
  }
  exit 1
}
Write-Host "All checks passed for envs/$Environment" -ForegroundColor Green

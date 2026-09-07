<#
.SYNOPSIS
  Destroy an on-demand environment after evidence capture.
.DESCRIPTION
  Pairs with the on-demand strategy: apply, prove, capture, destroy.
  The environment is disposable; the evidence is not.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)]
  [ValidateSet('dev', 'stage', 'prod')]
  [string]$Environment
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

Write-Host "About to DESTROY envs/$Environment." -ForegroundColor Yellow
Write-Host "Capture your evidence first:"
Write-Host "  - alert rules firing        - failover drill timings"
Write-Host "  - plan / apply output       - restore verification result"
Write-Host ""

$confirm = Read-Host "Type the environment name to confirm"
if ($confirm -ne $Environment) { Write-Host 'Aborted.'; exit 1 }

if ($PSCmdlet.ShouldProcess("envs/$Environment", 'terraform destroy')) {
  terraform -chdir="$root\envs\$Environment" destroy
}

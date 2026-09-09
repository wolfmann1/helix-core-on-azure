<#
.SYNOPSIS
  Install the pinned toolchain listed in dependencies.txt.

.DESCRIPTION
  Tries winget first, because winget packages are signed and therefore install
  on machines running Smart App Control or WDAC. Falls back to downloading the
  release asset from GitHub into .\.tools\bin when winget has no package or the
  install fails.

  Application Control policies block unsigned executables. If one is active,
  a downloaded binary may be refused even after a successful download, and the
  pip.exe shim is refused outright. Run with -Diagnose to see whether such a
  policy is in effect.

.PARAMETER Check
  Report what is missing without installing anything.

.PARAMETER Diagnose
  Report Application Control state and where each tool resolves from.

.EXAMPLE
  .\scripts\setup-env.ps1 -Check
  .\scripts\setup-env.ps1
  .\scripts\setup-env.ps1 -Diagnose
#>
[CmdletBinding()]
param(
  [switch]$Check,
  [switch]$Diagnose
)

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root '.tools\bin'
New-Item -ItemType Directory -Force -Path $tools | Out-Null
$env:PATH = "$tools;$env:PATH"

# --- Application Control detection ------------------------------------------
function Get-AppControlState {
  $state = [ordered]@{ SmartAppControl = 'unknown'; WDAC = 'unknown' }
  try {
    $k = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -ErrorAction Stop
    $state.SmartAppControl = switch ($k.VerifiedAndReputablePolicyState) {
      0 { 'off' } 1 { 'ON (blocks unsigned binaries)' } 2 { 'evaluation' } default { 'unknown' }
    }
  } catch { $state.SmartAppControl = 'not reported' }
  try {
    $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
    $state.WDAC = if ($dg.CodeIntegrityPolicyEnforcementStatus -gt 0) { 'enforcing' } else { 'not enforcing' }
  } catch { $state.WDAC = 'not reported' }
  return $state
}

if ($Diagnose) {
  Write-Host "Application Control state:" -ForegroundColor Cyan
  (Get-AppControlState).GetEnumerator() | ForEach-Object { Write-Host ("  {0,-16} {1}" -f $_.Key, $_.Value) }
  Write-Host ""
  $pyScripts = Get-PythonUserScripts
  Write-Host ("Python user Scripts dir: {0}" -f $(if ($pyScripts) { $pyScripts } else { 'not found' })) -ForegroundColor Cyan
  if ($pyScripts) {
    $onPath = ($env:PATH -split ';') -contains $pyScripts
    Write-Host ("  on PATH: {0}" -f $onPath)
    $env:PATH = "$pyScripts;$env:PATH"
  }
  Write-Host ""
  Write-Host "Tool resolution:" -ForegroundColor Cyan
  foreach ($t in 'terraform','tflint','az','gh','jq','checkov','winget','py','python','pip') {
    $c = Get-Command $t -ErrorAction SilentlyContinue
    Write-Host ("  {0,-12} {1}" -f $t, $(if ($c) { $c.Source } else { 'not found' }))
  }
  exit 0
}


# pip installs console scripts into the per-user Scripts directory, which is
# not on PATH by default. Ask Python where that is rather than guessing at the
# version-specific path.
function Get-PythonUserScripts {
  foreach ($py in 'py', 'python', 'python3') {
    if (-not (Get-Command $py -ErrorAction SilentlyContinue)) { continue }
    try {
      $out = & $py -c "import sysconfig;print(sysconfig.get_path('scripts', scheme='nt_user'))" 2>$null
      if ($LASTEXITCODE -eq 0 -and $out -and (Test-Path $out.Trim())) { return $out.Trim() }
    } catch { continue }
  }
  return $null
}

# --- GitHub release assets: naming is tool-specific -------------------------
function Get-GithubAsset {
  param([string]$Name, [string]$Version)
  switch ($Name) {
    'terraform' { return @{ Url = "https://releases.hashicorp.com/terraform/$Version/terraform_${Version}_windows_amd64.zip"; Zip = $true } }
    'tflint'    { return @{ Url = "https://github.com/terraform-linters/tflint/releases/download/v$Version/tflint_windows_amd64.zip"; Zip = $true } }
    'gh'        { return @{ Url = "https://github.com/cli/cli/releases/download/v$Version/gh_${Version}_windows_amd64.zip"; Zip = $true } }
    'jq'        { return @{ Url = "https://github.com/jqlang/jq/releases/download/jq-$Version/jq-windows-amd64.exe"; Zip = $false; Rename = 'jq.exe' } }
    default     { return $null }
  }
}

function Install-FromGithub {
  param([string]$Name, [string]$Version)
  $asset = Get-GithubAsset -Name $Name -Version $Version
  if (-not $asset) { Write-Warning "    no download recipe for $Name"; return $false }
  try {
    if ($asset.Zip) {
      $zip = Join-Path $env:TEMP "$Name-$Version.zip"
      Invoke-WebRequest $asset.Url -OutFile $zip -UseBasicParsing
      $stage = Join-Path $env:TEMP "$Name-$Version"
      Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
      Expand-Archive $zip -DestinationPath $stage -Force
      # gh ships inside bin\; everything else is flat
      Get-ChildItem $stage -Recurse -Filter '*.exe' | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $tools $_.Name) -Force
      }
    } else {
      $leaf = if ($asset.Rename) { $asset.Rename } else { "$Name.exe" }
      $out = Join-Path $tools $leaf
      Invoke-WebRequest $asset.Url -OutFile $out -UseBasicParsing
    }
    return $true
  } catch {
    Write-Warning "    download failed: $($_.Exception.Message)"
    return $false
  }
}

function Test-Present {
  param([string]$VerifyCommand)
  # winget puts shims on PATH for the current user, but not into this already
  # running process. Re-read PATH before deciding the install failed.
  $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
              [Environment]::GetEnvironmentVariable('PATH', 'User') + ";$tools"
  return [bool](Get-Command ($VerifyCommand -split ' ')[0] -ErrorAction SilentlyContinue)
}

function Install-FromWinget {
  param([string]$Id, [string]$VerifyCommand)
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $false }
  & winget install --id $Id --exact --silent `
      --accept-package-agreements --accept-source-agreements 2>&1 | Out-String | Write-Verbose
  # Exit codes vary between "installed", "already installed" and "no upgrade
  # found", so resolve the command instead of interpreting the code.
  return (Test-Present -VerifyCommand $VerifyCommand)
}

# checkov has no signed Windows installer. Try the launcher and the module form
# before the pip shim, since Application Control blocks the shim specifically.
function Install-Checkov {
  param([string]$Version)
  foreach ($cmd in @(
      @('py','-m','pip'),
      @('python','-m','pip'),
      @('python3','-m','pip')
  )) {
    if (-not (Get-Command $cmd[0] -ErrorAction SilentlyContinue)) { continue }
    try {
      & $cmd[0] $cmd[1] $cmd[2] install --quiet "checkov==$Version"
      if ($LASTEXITCODE -eq 0) { return $true }
    } catch { continue }
  }
  return $false
}

# --- main -------------------------------------------------------------------
$missing = @()

Get-Content (Join-Path $root 'dependencies.txt') |
  Where-Object { $_ -match '\|' -and $_ -notmatch '^\s*#' } |
  ForEach-Object {
    $p = $_ -split '\|' | ForEach-Object { $_.Trim() }
    $name, $version, $wingetId, $ghRepo, $verify = $p[0], $p[1], $p[2], $p[3], $p[4]

    if (Get-Command ($verify -split ' ')[0] -ErrorAction SilentlyContinue) {
      Write-Host ("  ok       {0,-11}" -f $name) -ForegroundColor Green
      return
    }
    if ($Check) {
      Write-Host ("  MISSING  {0,-11} (want {1})" -f $name, $version) -ForegroundColor Yellow
      $script:missing += $name
      return
    }

    Write-Host ("  install  {0,-11} {1}" -f $name, $version)

    if ($name -eq 'checkov') {
      if (Install-Checkov -Version $version) {
        Write-Host "    installed via python -m pip" -ForegroundColor Green
        # pip warns that its Scripts directory is not on PATH and carries on.
        # Without it the package is installed but the command does not resolve.
        $pyScripts = Get-PythonUserScripts
        if ($pyScripts) {
          $env:PATH = "$pyScripts;$env:PATH"
          if (Get-Command checkov -ErrorAction SilentlyContinue) {
            Write-Host "    found at $pyScripts" -ForegroundColor Green
            Write-Host ""
            Write-Host "    That directory is not on your PATH. ci-checks.ps1 adds it per run." -ForegroundColor DarkGray
            Write-Host "    To make it permanent for your account:" -ForegroundColor DarkGray
            Write-Host "      [Environment]::SetEnvironmentVariable('PATH'," -ForegroundColor DarkGray
            Write-Host "        [Environment]::GetEnvironmentVariable('PATH','User') + ';$pyScripts', 'User')" -ForegroundColor DarkGray
          } else {
            Write-Host "    installed, but checkov still does not resolve" -ForegroundColor Yellow
            $script:missing += $name
          }
        }
      } else {
        Write-Host "    SKIPPED. No signed Windows installer, and the pip shim is" -ForegroundColor Yellow
        Write-Host "    blocked by this machine's Application Control policy." -ForegroundColor Yellow
        Write-Host "    The pipeline runs checkov on Linux, so this only affects the" -ForegroundColor Yellow
        Write-Host "    local scan step. Use ci-checks.ps1 -SkipScan until then." -ForegroundColor Yellow
        $script:missing += $name
      }
      return
    }

    $done = $false
    if ($wingetId -ne '-') {
      $done = Install-FromWinget -Id $wingetId -VerifyCommand $verify
      if ($done) { Write-Host "    installed via winget ($wingetId)" -ForegroundColor Green }
    }
    if (-not $done -and $ghRepo -ne '-') {
      Write-Host "    winget unavailable or failed; downloading release asset"
      $done = Install-FromGithub -Name $name -Version $version
      if ($done -and -not (Test-Present -VerifyCommand $verify)) {
        Write-Host "    downloaded, but the binary will not run. On a machine with" -ForegroundColor Yellow
        Write-Host "    Application Control this usually means it is unsigned." -ForegroundColor Yellow
        $done = $false
      } elseif ($done) {
        Write-Host "    installed into .\.tools\bin" -ForegroundColor Green
      }
    }
    if (-not $done) { $script:missing += $name }
  }

Write-Host ""
if ($missing.Count -gt 0) {
  Write-Host "Not installed: $($missing -join ', ')" -ForegroundColor Yellow
  $state = Get-AppControlState
  if ($state.SmartAppControl -like 'ON*' -or $state.WDAC -eq 'enforcing') {
    Write-Host ""
    Write-Host "An Application Control policy is active on this machine, which blocks" -ForegroundColor Yellow
    Write-Host "unsigned executables. Prefer winget packages; they are signed." -ForegroundColor Yellow
    Write-Host "Run .\scripts\setup-env.ps1 -Diagnose for detail." -ForegroundColor Yellow
  }
  exit 1
}
Write-Host "Toolchain complete." -ForegroundColor Green

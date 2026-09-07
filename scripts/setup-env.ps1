<#
.SYNOPSIS
  Windows counterpart to setup-env.sh. Reads the same dependencies.txt.
.NOTES
  Uses winget where dependencies.txt names a winget source, direct download
  otherwise. Same pin-everything rule applies.
#>
[CmdletBinding()]
param([switch]$Check)

$root  = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root '.tools\bin'
New-Item -ItemType Directory -Force -Path $tools | Out-Null

Get-Content (Join-Path $root 'dependencies.txt') |
  Where-Object { $_ -match '\|' -and $_ -notmatch '^\s*#' } |
  ForEach-Object {
    $p = $_ -split '\|' | ForEach-Object { $_.Trim() }
    $name, $version, $source, $verify = $p[0], $p[1], $p[2], $p[3]

    if (Get-Command ($verify -split ' ')[0] -ErrorAction SilentlyContinue) {
      Write-Host ("  ok      {0,-12}" -f $name); return
    }
    if ($Check) { Write-Host ("  MISSING {0,-12} (want {1})" -f $name, $version); return }

    Write-Host ("  install {0,-12} {1}" -f $name, $version)
    switch -Wildcard ($source) {
      'winget:*'   { winget install --id ($source -replace '^winget:','') --silent --accept-package-agreements }
      'hashicorp'  {
        $url = "https://releases.hashicorp.com/$name/$version/${name}_${version}_windows_amd64.zip"
        $zip = Join-Path $env:TEMP "$name.zip"
        Invoke-WebRequest $url -OutFile $zip
        Expand-Archive $zip -DestinationPath $tools -Force
      }
      'pip'        { pip install "$name==$version" }
      default      { Write-Warning "unhandled source '$source' for $name" }
    }
  }

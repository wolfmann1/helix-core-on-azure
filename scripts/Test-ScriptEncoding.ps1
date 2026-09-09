<#
.SYNOPSIS
  Fail if any .ps1 file contains a non-ASCII character.

.DESCRIPTION
  Windows PowerShell 5.1 reads .ps1 files using the system ANSI code page
  unless the file carries a UTF-8 BOM. A UTF-8 em-dash is then read as two
  bytes, which breaks string quoting and leaks source text into the output at
  runtime. The script parses, so nothing catches it until it runs.

  Keeping .ps1 files pure ASCII avoids the problem on both 5.1 and 7, and needs
  no BOM. Use "--" instead of an em-dash and straight quotes throughout.

.EXAMPLE
  .\scripts\Test-ScriptEncoding.ps1
#>
[CmdletBinding()]
param([string]$Path = (Split-Path -Parent $PSScriptRoot))

$bad = @()
Get-ChildItem -Path $Path -Recurse -Filter *.ps1 -File |
  Where-Object { $_.FullName -notmatch '\\\.git\\' } |
  ForEach-Object {
    $offenders = [System.IO.File]::ReadAllText($_.FullName).ToCharArray() |
                 Where-Object { [int]$_ -gt 127 } | Select-Object -Unique
    if ($offenders) {
      $bad += [pscustomobject]@{
        File  = $_.FullName.Replace("$Path\", '')
        Chars = ($offenders | ForEach-Object { "U+{0:X4}" -f [int]$_ }) -join ' '
      }
    }
  }

if ($bad) {
  Write-Host "Non-ASCII characters found in PowerShell scripts:" -ForegroundColor Red
  $bad | Format-Table -AutoSize
  Write-Host "Replace them with ASCII equivalents. See the note in this script." -ForegroundColor Yellow
  exit 1
}
Write-Host "All .ps1 files are ASCII." -ForegroundColor Green

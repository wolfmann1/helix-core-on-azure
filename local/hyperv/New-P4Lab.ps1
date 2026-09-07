<#
.SYNOPSIS
  Stand up the Perforce lab on Hyper-V using the same provisioning scripts
  the Azure modules use.
.DESCRIPTION
  Creates VMs from vm-manifest.json, attaches the three data VHDs with the
  volume labels provisioning/common/volumes.sh expects (p4db, p4logs,
  p4depots), then runs provisioning/provision.sh over SSH.

  Requires: Hyper-V role, an Ubuntu 24.04 LTS cloud image, and OpenSSH client.
.NOTES
  TODO(chris): cloud-init seed ISO generation for the Ubuntu cloud image.
#>
[CmdletBinding()]
param(
  [string]$Manifest = "$PSScriptRoot\vm-manifest.json",
  [string]$SwitchName = 'P4Lab',
  [string]$VhdRoot = 'D:\HyperV\P4Lab',
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$spec = Get-Content $Manifest | ConvertFrom-Json

if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
  Write-Host "Creating internal switch $SwitchName"
  if (-not $WhatIf) { New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null }
}

foreach ($vm in $spec.vms) {
  Write-Host "== $($vm.name)  role=$($vm.role)  $($vm.vcpu) vCPU / $($vm.memoryGB) GB"
  if ($WhatIf) { continue }

  New-VM -Name $vm.name -Generation 2 -MemoryStartupBytes ($vm.memoryGB * 1GB) `
         -SwitchName $SwitchName -Path $VhdRoot | Out-Null
  Set-VMProcessor -VMName $vm.name -Count $vm.vcpu

  $disks = @($vm.dataDisks)
  if ($spec.defaults.separateSdpVolumes -and $vm.optionalDisks) {
    $disks += @($vm.optionalDisks | Where-Object { $_.when -eq 'separateSdpVolumes' })
  }
  if (-not $spec.defaults.splitMetadata) {
    $disks = $disks | Where-Object { $_.label -ne 'p4db2' }
  }

  foreach ($d in $disks) {
    $vhd = Join-Path $VhdRoot "$($vm.name)-$($d.label).vhdx"
    New-VHD -Path $vhd -SizeBytes ($d.sizeGB * 1GB) -Dynamic | Out-Null
    Add-VMHardDiskDrive -VMName $vm.name -Path $vhd
    # Label is applied inside the guest; volumes.sh mounts by LABEL=, which is
    # what keeps the Azure and Hyper-V paths identical.
    Write-Host "   disk $($d.label) $($d.sizeGB)GB -> $vhd"
  }
}

Write-Host ""
Write-Host "Next: boot each VM, then from an SSH session run:"
Write-Host "  sudo ./provisioning/provision.sh --role <role> --install-sdp true \"
Write-Host "       --commit-host <ip> --serverlocks-mb $($spec.defaults.serverlocksTmpfsMB)"
Write-Host ""
Write-Host "Label each data VHD inside the guest to match its 'label' value;"
Write-Host "provisioning/common/volumes.sh mounts by LABEL=, which is what keeps"
Write-Host "the Azure and Hyper-V paths identical."

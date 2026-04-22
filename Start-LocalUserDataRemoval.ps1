[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateRange(0, 3650)]
    [int]$InactivityDays = 60,

    [ValidateRange(0, 100000)]
    [int]$MaxProfileSizeMB = 500,

    [ValidateNotNullOrEmpty()]
    [string]$ProfileRoot = 'C:\Users',

    [string[]]$ExcludeUserName = @(
        'Default',
        'Default User',
        'Public',
        'All Users',
        'Administrator',
        'WDAGUtilityAccount'
    ),

    [string[]]$ExcludeProfilePath = @(),

    [string]$LogPath
)

Import-Module -Force (Join-Path -Path $PSScriptRoot -ChildPath 'LocalUserDataRemover.psd1')

Start-LocalUserDataRemoval @PSBoundParameters

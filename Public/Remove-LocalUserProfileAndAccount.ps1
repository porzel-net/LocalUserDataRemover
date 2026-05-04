function Remove-LocalUserProfileAndAccount {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalUserName,

        [ValidateNotNullOrEmpty()]
        [string]$ProfileRoot = 'C:\Users',

        [string]$LogPath
    )

    $effectiveLogPath = if ([string]::IsNullOrWhiteSpace($LogPath)) {
        Get-LocalUserDataRemoverDefaultLogPath
    } else {
        $LogPath
    }

    $effectiveLogPath = Write-LocalUserDataRemoverLog -LogPath $effectiveLogPath -Level 'Info' -Message (
        'Starting targeted removal for local user {0}. Root={1}' -f $LocalUserName, $ProfileRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($effectiveLogPath)) {
        Write-Verbose ('Logging to {0}' -f $effectiveLogPath)
    }

    if (-not (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) -or -not (Get-Command Remove-LocalUser -ErrorAction SilentlyContinue)) {
        throw 'Remove-LocalUserProfileAndAccount requires the Microsoft.PowerShell.LocalAccounts cmdlets Get-LocalUser and Remove-LocalUser.'
    }

    $localUser = Get-LocalUser -Name $LocalUserName -ErrorAction Stop
    $sid = [string]$localUser.SID

    if ([string]::IsNullOrWhiteSpace($sid)) {
        throw ('Could not resolve a SID for local user {0}.' -f $LocalUserName)
    }

    $profiles = Get-LocalUserProfileCandidates -ProfileRoot $ProfileRoot -Sid $sid
    $profile = $profiles | Select-Object -First 1

    $profilePath = if ($null -ne $profile) { $profile.LocalPath } else { '' }
    $profileDeleted = $false
    $accountDeleted = $false
    $actionDescription = if ([string]::IsNullOrWhiteSpace($profilePath)) {
        'remove local user account'
    } else {
        'remove local user account and profile'
    }

    if ($PSCmdlet.ShouldProcess($LocalUserName, $actionDescription)) {
        try {
            if ($null -ne $profile) {
                Remove-LocalUserProfile -Profile $profile -ErrorAction Stop
                $profileDeleted = $true
                Write-LocalUserDataRemoverLog -LogPath $effectiveLogPath -Level 'Delete' -Message (
                    'Deleted local profile {0} for {1}' -f $profilePath, $LocalUserName
                )
            } else {
                Write-LocalUserDataRemoverLog -LogPath $effectiveLogPath -Level 'Skip' -Message (
                    'No local profile found for {0}; removing account only' -f $LocalUserName
                )
            }

            Remove-LocalUser -Name $LocalUserName -Confirm:$false -ErrorAction Stop
            $accountDeleted = $true

            Write-LocalUserDataRemoverLog -LogPath $effectiveLogPath -Level 'Delete' -Message (
                'Deleted local user account {0}' -f $LocalUserName
            )
        } catch {
            Write-LocalUserDataRemoverLog -LogPath $effectiveLogPath -Level 'Error' -Message (
                'Failed to remove local user {0}: {1}' -f $LocalUserName, $_.Exception.Message
            )
            throw
        }
    } else {
        Write-LocalUserDataRemoverLog -LogPath $effectiveLogPath -Level 'Skip' -Message (
            'WhatIf prevented removal of local user {0}' -f $LocalUserName
        )
    }

    Write-LocalUserDataRemoverLog -LogPath $effectiveLogPath -Level 'Summary' -Message (
        'Finished targeted removal for local user {0}' -f $LocalUserName
    )

    return [pscustomobject]@{
        LocalUserName = $LocalUserName
        SID           = $sid
        ProfilePath    = $profilePath
        ProfileDeleted = $profileDeleted
        AccountDeleted = $accountDeleted
        LogPath        = $effectiveLogPath
    }
}

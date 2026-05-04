function Start-LocalUserDataRemoval {
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

    $options = [CleanupOptions]::new(
        $InactivityDays,
        $MaxProfileSizeMB,
        $ProfileRoot,
        $ExcludeUserName,
        $ExcludeProfilePath
    )

    $result = [CleanupResult]::new()
    $effectiveLogPath = if ([string]::IsNullOrWhiteSpace($LogPath)) {
        Get-LocalUserDataRemoverDefaultLogPath
    } else {
        $LogPath
    }

    $effectiveLogPath = Write-LocalUserDataRemoverLog -LogPath $effectiveLogPath -Level 'Info' -Message (
        'Starting scan. Root={0}; InactivityDays={1}; MaxProfileSizeMB={2}' -f
        $options.ProfileRoot,
        $options.InactivityDays,
        [math]::Round($options.MaxProfileSizeBytes / 1MB, 2)
    )

    if (-not [string]::IsNullOrWhiteSpace($effectiveLogPath)) {
        Write-Verbose ('Logging to {0}' -f $effectiveLogPath)
    }

    $profiles = Get-LocalUserProfileCandidates -ProfileRoot $options.ProfileRoot

    foreach ($profile in $profiles) {
        $result.AddScanned()
        $decision = Test-LocalUserProfileCandidate -Profile $profile -Options $options

        $entry = [pscustomobject]@{
            SID           = $profile.SID
            UserName      = $profile.UserName
            LocalPath     = $profile.LocalPath
            ProfileFolder = $profile.ProfileFolderName
            LastUseTime   = $profile.LastUseTime
            SizeBytes     = [int64]$profile.SizeBytes
            Reasons       = $decision.Reasons
        }

        if (-not $decision.ShouldDelete) {
            $result.AddSkipped($entry)
            Write-LocalUserDataRemoverLog -LogPath $effectiveLogPath -Level 'Skip' -Message (
                'Skipped profile {0} ({1}): {2}' -f $profile.LocalPath, $profile.UserName, ($decision.Reasons -join '; ')
            )
            continue
        }

        $actionDescription = if ($decision.IsOld -and $decision.IsLarge) {
            'delete stale and oversized local profile'
        } elseif ($decision.IsOld) {
            'delete stale local profile'
        } else {
            'delete oversized local profile'
        }

        if ($PSCmdlet.ShouldProcess($profile.LocalPath, $actionDescription)) {
            try {
                Remove-LocalUserProfile -Profile $profile -ErrorAction Stop
                $result.AddDeleted($entry)

                Write-LocalUserDataRemoverLog -LogPath $effectiveLogPath -Level 'Delete' -Message (
                    'Deleted profile {0} ({1})' -f $profile.LocalPath, $profile.UserName
                )
            } catch {
                $failureEntry = [pscustomobject]@{
                    SID           = $profile.SID
                    UserName      = $profile.UserName
                    LocalPath     = $profile.LocalPath
                    ProfileFolder = $profile.ProfileFolderName
                    LastUseTime   = $profile.LastUseTime
                    SizeBytes     = [int64]$profile.SizeBytes
                    Error         = $_.Exception.Message
                }

                $result.AddFailed($failureEntry)

                Write-LocalUserDataRemoverLog -LogPath $effectiveLogPath -Level 'Error' -Message (
                    'Failed to delete profile {0} ({1}): {2}' -f $profile.LocalPath, $profile.UserName, $_.Exception.Message
                )
            }
        } else {
            $result.AddSkipped($entry)
            Write-LocalUserDataRemoverLog -LogPath $effectiveLogPath -Level 'Skip' -Message (
                'WhatIf prevented deletion of profile {0} ({1})' -f $profile.LocalPath, $profile.UserName
            )
        }
    }

    Write-LocalUserDataRemoverLog -LogPath $effectiveLogPath -Level 'Summary' -Message (
        'Finished scan. Scanned={0}; Deleted={1}; Skipped={2}; Failed={3}' -f
        $result.ScannedCount,
        $result.DeletedCount,
        $result.SkippedCount,
        $result.FailedCount
    )

    return $result
}

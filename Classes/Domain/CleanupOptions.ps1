class CleanupOptions {
    [int]$InactivityDays
    [long]$MaxProfileSizeBytes
    [string]$ProfileRoot
    [string[]]$ExcludeUserNames
    [string[]]$ExcludeProfilePaths

    CleanupOptions(
        [int]$InactivityDays,
        [int]$MaxProfileSizeMB,
        [string]$ProfileRoot,
        [string[]]$ExcludeUserNames,
        [string[]]$ExcludeProfilePaths
    ) {
        if ($InactivityDays -lt 0) {
            throw [System.ArgumentOutOfRangeException]::new('InactivityDays', 'Must be 0 or greater.')
        }

        if ($MaxProfileSizeMB -lt 0) {
            throw [System.ArgumentOutOfRangeException]::new('MaxProfileSizeMB', 'Must be 0 or greater.')
        }

        if ([string]::IsNullOrWhiteSpace($ProfileRoot)) {
            throw [System.ArgumentException]::new('ProfileRoot must not be empty.', 'ProfileRoot')
        }

        $this.InactivityDays = $InactivityDays
        $this.MaxProfileSizeBytes = [int64]$MaxProfileSizeMB * 1MB
        $this.ProfileRoot = [CleanupOptions]::NormalizePath($ProfileRoot)
        $this.ExcludeUserNames = @($ExcludeUserNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $this.ExcludeProfilePaths = @(
            $ExcludeProfilePaths |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { [CleanupOptions]::NormalizePath($_) }
        )
    }

    static [string] NormalizeText([string]$Value) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return ''
        }

        return $Value.Trim().ToLowerInvariant()
    }

    static [string] NormalizePath([string]$Value) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return ''
        }

        try {
            return [System.IO.Path]::GetFullPath($Value).TrimEnd('\')
        } catch {
            return $Value.Trim().TrimEnd('\')
        }
    }

    static [bool] TextEquals([string]$Left, [string]$Right) {
        return ([CleanupOptions]::NormalizeText($Left) -eq [CleanupOptions]::NormalizeText($Right))
    }

    static [bool] PathEquals([string]$Left, [string]$Right) {
        return ([CleanupOptions]::NormalizePath($Left) -eq [CleanupOptions]::NormalizePath($Right))
    }

    [datetime] GetCutoffDate() {
        return (Get-Date).AddDays(-1 * $this.InactivityDays)
    }

    [bool] IsExcluded([LocalProfileCandidate]$Profile) {
        if ($null -eq $Profile) {
            return $false
        }

        foreach ($userName in $this.ExcludeUserNames) {
            if (
                [CleanupOptions]::TextEquals($userName, $Profile.UserName) -or
                [CleanupOptions]::TextEquals($userName, $Profile.ProfileFolderName) -or
                [CleanupOptions]::TextEquals($userName, $Profile.SID)
            ) {
                return $true
            }
        }

        foreach ($path in $this.ExcludeProfilePaths) {
            if ([CleanupOptions]::PathEquals($path, $Profile.LocalPath)) {
                return $true
            }
        }

        return $false
    }
}

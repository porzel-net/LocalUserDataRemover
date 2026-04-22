function Test-LocalUserProfileCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [LocalProfileCandidate]$Profile,

        [Parameter(Mandatory)]
        [CleanupOptions]$Options
    )

    $skipReasons = [System.Collections.ArrayList]::new()
    $deleteReasons = [System.Collections.ArrayList]::new()

    if ($Profile.Special) {
        $skipReasons.Add('Special profile')
    }

    if ($Profile.Loaded) {
        $skipReasons.Add('Profile is currently loaded')
    }

    if (-not (Test-LocalUserDataRemoverPathUnderRoot -Path $Profile.LocalPath -Root $Options.ProfileRoot)) {
        $skipReasons.Add('Profile is outside the target root')
    }

    if ($Options.IsExcluded($Profile)) {
        $skipReasons.Add('Profile is excluded by policy')
    }

    $cutoffDate = $Options.GetCutoffDate()
    $isOld = $false

    if ($Profile.LastUseTime -ne [datetime]::MinValue) {
        $isOld = ($Profile.LastUseTime -lt $cutoffDate)
    }

    $isLarge = ([int64]$Profile.SizeBytes -ge $Options.MaxProfileSizeBytes)

    if ($skipReasons.Count -eq 0) {
        if ($isOld) {
            $deleteReasons.Add(('Inactive for {0} days or more' -f $Options.InactivityDays))
        }

        if ($isLarge) {
            $deleteReasons.Add(('Profile size is above {0} MB' -f ([math]::Round($Options.MaxProfileSizeBytes / 1MB, 2))))
        }
    }

    $shouldDelete = ($skipReasons.Count -eq 0) -and ($isOld -or $isLarge)

    if (-not $shouldDelete -and $skipReasons.Count -eq 0) {
        $skipReasons.Add('Profile does not meet the age or size threshold')
    }

    return [pscustomobject]@{
        ShouldDelete = $shouldDelete
        IsOld        = $isOld
        IsLarge      = $isLarge
        CutoffDate   = $cutoffDate
        SizeBytes    = [int64]$Profile.SizeBytes
        Reasons      = if ($shouldDelete) { $deleteReasons.ToArray() } else { $skipReasons.ToArray() }
    }
}

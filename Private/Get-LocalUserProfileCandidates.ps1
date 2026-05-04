function Get-LocalUserProfileCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileRoot,

        [string]$Sid
    )

    $items = New-Object System.Collections.ArrayList

    if ([string]::IsNullOrWhiteSpace($Sid)) {
        $profileInstances = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop
    } else {
        $escapedSid = $Sid.Replace("'", "''")
        $profileInstances = @(Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$escapedSid'" -ErrorAction Stop)
        if ($profileInstances.Count -eq 1 -and $null -eq $profileInstances[0]) {
            $profileInstances = @()
        }
    }

    foreach ($profileInstance in $profileInstances) {
        $localPath = [string]$profileInstance.LocalPath

        if (-not (Test-LocalUserDataRemoverPathUnderRoot -Path $localPath -Root $ProfileRoot)) {
            continue
        }

        $candidate = [LocalProfileCandidate]::new()
        $candidate.SID = [string]$profileInstance.SID
        $candidate.LocalPath = $localPath
        $candidate.ProfileFolderName = if ([string]::IsNullOrWhiteSpace($localPath)) { '' } else { Split-Path -Path $localPath -Leaf }
        $candidate.UserName = Resolve-LocalUserDataRemoverAccountName -Sid $candidate.SID -LocalPath $candidate.LocalPath
        $candidate.LastUseTime = ConvertFrom-LocalUserDataRemoverCimDateTime -Value $profileInstance.LastUseTime
        $candidate.Loaded = [bool]$profileInstance.Loaded
        $candidate.Special = [bool]$profileInstance.Special
        $candidate.SizeBytes = Get-LocalProfileSizeBytes -ProfileInstance $profileInstance -LocalPath $candidate.LocalPath
        $candidate.SourceInstance = $profileInstance

        [void]$items.Add($candidate)
    }

    return $items.ToArray()
}

function Get-LocalProfileSizeBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ProfileInstance,

        [Parameter(Mandatory)]
        [string]$LocalPath
    )

    $size = [int64]0
    $sizeProperty = $ProfileInstance.PSObject.Properties['Size']

    if ($null -ne $sizeProperty) {
        try {
            $size = [int64]$ProfileInstance.Size
        } catch {
            $size = [int64]0
        }
    }

    if ($size -gt 0) {
        return $size
    }

    return Get-LocalUserDataRemoverFolderSizeBytes -Path $LocalPath
}

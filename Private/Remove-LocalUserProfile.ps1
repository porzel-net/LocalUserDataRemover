function Remove-LocalUserProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [LocalProfileCandidate]$Profile
    )

    if ($null -eq $Profile.SourceInstance -and [string]::IsNullOrWhiteSpace($Profile.SID)) {
        throw 'Profile must contain either a CIM instance or a SID.'
    }

    $cimProfile = $Profile.SourceInstance
    $escapedSid = $null

    if ([string]::IsNullOrWhiteSpace($Profile.SID) -eq $false) {
        $escapedSid = $Profile.SID.Replace("'", "''")
    }

    if ($null -eq $cimProfile -or $cimProfile -isnot [Microsoft.Management.Infrastructure.CimInstance]) {
        if ([string]::IsNullOrWhiteSpace($escapedSid)) {
            throw 'Profile must contain a SID when no CIM instance is available.'
        }

        try {
            $cimProfile = Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$escapedSid'" -ErrorAction Stop
        } catch {
            if ($null -eq $cimProfile) {
                throw
            }
        }
    }

    if ($cimProfile -is [Microsoft.Management.Infrastructure.CimInstance]) {
        $deleteResult = Invoke-CimMethod -InputObject $cimProfile -MethodName Delete -ErrorAction Stop
    } else {
        $deleteResult = Invoke-CimMethod -ClassName Win32_UserProfile -Query "SELECT * FROM Win32_UserProfile WHERE SID='$escapedSid'" -MethodName Delete -ErrorAction Stop
    }

    if ($null -ne $deleteResult -and $null -ne $deleteResult.ReturnValue -and [int]$deleteResult.ReturnValue -ne 0) {
        throw ('Profile deletion failed with return value {0}.' -f $deleteResult.ReturnValue)
    }

    return $true
}

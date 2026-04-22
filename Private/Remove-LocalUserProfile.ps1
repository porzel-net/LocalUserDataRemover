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

    if ($null -eq $cimProfile) {
        $escapedSid = $Profile.SID.Replace("'", "''")
        $cimProfile = Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$escapedSid'" -ErrorAction Stop
    }

    $deleteResult = Invoke-CimMethod -InputObject $cimProfile -MethodName Delete -ErrorAction Stop

    if ($null -ne $deleteResult -and $null -ne $deleteResult.ReturnValue -and [int]$deleteResult.ReturnValue -ne 0) {
        throw ('Profile deletion failed with return value {0}.' -f $deleteResult.ReturnValue)
    }

    return $true
}

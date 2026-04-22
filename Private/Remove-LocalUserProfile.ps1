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

    if ($null -ne $cimProfile) {
        $deleteMethod = $cimProfile.PSObject.Methods['Delete']

        if ($null -ne $deleteMethod) {
            $deleteResult = $deleteMethod.Invoke()
        } elseif ($cimProfile -is [Microsoft.Management.Infrastructure.CimInstance]) {
            $deleteResult = Invoke-CimMethod -InputObject $cimProfile -MethodName Delete -ErrorAction Stop
        } else {
            $cimProfile = $null
        }
    }

    if ($null -eq $cimProfile) {
        if ([string]::IsNullOrWhiteSpace($Profile.SID)) {
            throw 'Profile must contain a SID when no CIM instance is available.'
        }

        $escapedSid = $Profile.SID.Replace("'", "''")
        $cimProfile = Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$escapedSid'" -ErrorAction Stop

        if ($cimProfile -is [Microsoft.Management.Infrastructure.CimInstance]) {
            $deleteResult = Invoke-CimMethod -InputObject $cimProfile -MethodName Delete -ErrorAction Stop
        } else {
            $deleteMethod = $cimProfile.PSObject.Methods['Delete']
            if ($null -eq $deleteMethod) {
                throw 'Retrieved profile does not expose a delete method.'
            }

            $deleteResult = $deleteMethod.Invoke()
        }
    }

    if ($null -ne $deleteResult -and $null -ne $deleteResult.ReturnValue -and [int]$deleteResult.ReturnValue -ne 0) {
        throw ('Profile deletion failed with return value {0}.' -f $deleteResult.ReturnValue)
    }

    return $true
}

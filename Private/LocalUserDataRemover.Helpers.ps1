function Get-LocalUserDataRemoverNormalizedPath {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $trimmed = $Path.Trim()

    if ($trimmed -match '^[A-Za-z]:[\\/]' -or $trimmed.StartsWith('\\')) {
        return ($trimmed -replace '/', '\').TrimEnd('\')
    }

    try {
        return [System.IO.Path]::GetFullPath($trimmed).TrimEnd('\')
    } catch {
        return $trimmed.TrimEnd('\')
    }
}

function Test-LocalUserDataRemoverPathUnderRoot {
    [CmdletBinding()]
    param(
        [string]$Path,

        [string]$Root
    )

    $normalizedPath = Get-LocalUserDataRemoverNormalizedPath -Path $Path
    $normalizedRoot = Get-LocalUserDataRemoverNormalizedPath -Path $Root

    if ([string]::IsNullOrWhiteSpace($normalizedPath) -or [string]::IsNullOrWhiteSpace($normalizedRoot)) {
        return $false
    }

    if ($normalizedPath.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return $normalizedPath.StartsWith(($normalizedRoot + '\'), [System.StringComparison]::OrdinalIgnoreCase)
}

function ConvertFrom-LocalUserDataRemoverCimDateTime {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return [datetime]::MinValue
    }

    if ($Value -is [datetime]) {
        return [datetime]$Value
    }

    try {
        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) {
            return [datetime]::MinValue
        }

        return [System.Management.ManagementDateTimeConverter]::ToDateTime($text)
    } catch {
        return [datetime]::MinValue
    }
}

function Resolve-LocalUserDataRemoverAccountName {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Sid,

        [AllowNull()]
        [string]$LocalPath
    )

    if (-not [string]::IsNullOrWhiteSpace($Sid)) {
        try {
            $sidObject = [System.Security.Principal.SecurityIdentifier]::new($Sid)
            $ntAccount = $sidObject.Translate([System.Security.Principal.NTAccount])
            return $ntAccount.Value
        } catch {
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($LocalPath)) {
        return Split-Path -Path $LocalPath -Leaf
    }

    return $Sid
}

function Get-LocalUserDataRemoverFolderSizeBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [int64]0
    }

    $totalBytes = [int64]0
    $stack = New-Object System.Collections.Stack

    try {
        $stack.Push((Get-Item -LiteralPath $Path -ErrorAction Stop))
    } catch {
        return [int64]0
    }

    while ($stack.Count -gt 0) {
        $directory = [System.IO.DirectoryInfo]$stack.Pop()

        try {
            foreach ($file in $directory.EnumerateFiles()) {
                $totalBytes += [int64]$file.Length
            }

            foreach ($subDirectory in $directory.EnumerateDirectories()) {
                if (($subDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    continue
                }

                $stack.Push($subDirectory)
            }
        } catch {
            continue
        }
    }

    return $totalBytes
}

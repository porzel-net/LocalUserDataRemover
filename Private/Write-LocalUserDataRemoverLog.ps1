function Write-LocalUserDataRemoverLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [string]$LogPath,

        [ValidateSet('Info', 'Warning', 'Error', 'Delete', 'Skip', 'Summary')]
        [string]$Level = 'Info'
    )

    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        return
    }

    $resolvedLogPath = Resolve-LocalUserDataRemoverLogPath -Path $LogPath
    $logDirectory = Split-Path -Path $resolvedLogPath -Parent

    if (-not [string]::IsNullOrWhiteSpace($logDirectory) -and -not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level.ToUpperInvariant(), $Message

    if (-not (Test-Path -LiteralPath $resolvedLogPath)) {
        New-Item -ItemType File -Path $resolvedLogPath -Force | Out-Null
    }

    Add-Content -LiteralPath $resolvedLogPath -Value $line -Encoding UTF8

    return $resolvedLogPath
}

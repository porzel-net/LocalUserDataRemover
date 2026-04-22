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

    $logDirectory = Split-Path -Path $LogPath -Parent

    if (-not [string]::IsNullOrWhiteSpace($logDirectory) -and -not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level.ToUpperInvariant(), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

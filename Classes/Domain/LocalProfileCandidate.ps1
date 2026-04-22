class LocalProfileCandidate {
    [string]$SID
    [string]$UserName
    [string]$ProfileFolderName
    [string]$LocalPath
    [datetime]$LastUseTime
    [bool]$Loaded
    [bool]$Special
    [long]$SizeBytes
    [object]$SourceInstance

    LocalProfileCandidate() {
        $this.SID = ''
        $this.UserName = ''
        $this.ProfileFolderName = ''
        $this.LocalPath = ''
        $this.LastUseTime = [datetime]::MinValue
        $this.Loaded = $false
        $this.Special = $false
        $this.SizeBytes = 0
        $this.SourceInstance = $null
    }
}

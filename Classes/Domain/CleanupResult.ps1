class CleanupResult {
    [int]$ScannedCount
    [int]$DeletedCount
    [int]$SkippedCount
    [int]$FailedCount
    [System.Collections.ArrayList]$DeletedProfiles
    [System.Collections.ArrayList]$SkippedProfiles
    [System.Collections.ArrayList]$FailedProfiles

    CleanupResult() {
        $this.ScannedCount = 0
        $this.DeletedCount = 0
        $this.SkippedCount = 0
        $this.FailedCount = 0
        $this.DeletedProfiles = [System.Collections.ArrayList]::new()
        $this.SkippedProfiles = [System.Collections.ArrayList]::new()
        $this.FailedProfiles = [System.Collections.ArrayList]::new()
    }

    [void] AddScanned() {
        $this.ScannedCount++
    }

    [void] AddDeleted([object]$Entry) {
        [void]$this.DeletedProfiles.Add($Entry)
        $this.DeletedCount++
    }

    [void] AddSkipped([object]$Entry) {
        [void]$this.SkippedProfiles.Add($Entry)
        $this.SkippedCount++
    }

    [void] AddFailed([object]$Entry) {
        [void]$this.FailedProfiles.Add($Entry)
        $this.FailedCount++
    }
}

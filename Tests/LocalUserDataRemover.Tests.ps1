$modulePath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') -ChildPath 'LocalUserDataRemover.psd1'
Import-Module $modulePath -Force

if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
    function global:Get-CimInstance {
        [CmdletBinding()]
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [object[]]$RemainingArguments
        )
    }
}

InModuleScope LocalUserDataRemover {
    BeforeAll {
        function New-LocalUserDataRemoverProfileStub {
            param(
                [Parameter(Mandatory)]
                [string]$Sid,

                [Parameter(Mandatory)]
                [string]$LocalPath,

                [AllowNull()]
                [string]$LastUseTime = $null,

                [bool]$Loaded = $false,

                [bool]$Special = $false,

                [long]$Size = 0
            )

            $profile = [pscustomobject]@{
                SID         = $Sid
                LocalPath   = $LocalPath
                LastUseTime = $LastUseTime
                Loaded      = $Loaded
                Special     = $Special
                Size        = $Size
            }

            $profile | Add-Member -MemberType ScriptMethod -Name Delete -Value {
                [pscustomobject]@{ ReturnValue = 0 }
            } -Force

            return $profile
        }
    }

    Describe 'CleanupOptions' {
        It 'normalizes text and paths consistently' {
            [CleanupOptions]::NormalizeText('  TeSt  ') | Should -Be 'test'
            [CleanupOptions]::NormalizeText($null) | Should -Be ''
            [CleanupOptions]::NormalizePath('C:\Users\Public\\') | Should -Be 'C:\Users\Public'
        }

        It 'converts megabytes to bytes' {
            $options = [CleanupOptions]::new(60, 500, 'C:\Users', @(), @())

            $options.MaxProfileSizeBytes | Should -Be 524288000
        }

        It 'rejects invalid constructor arguments' {
            { [CleanupOptions]::new(-1, 500, 'C:\Users', @(), @()) } | Should -Throw
            { [CleanupOptions]::new(60, -1, 'C:\Users', @(), @()) } | Should -Throw
            { [CleanupOptions]::new(60, 500, '   ', @(), @()) } | Should -Throw
        }

        It 'computes a cutoff date in the past' {
            $options = [CleanupOptions]::new(60, 500, 'C:\Users', @(), @())

            $options.GetCutoffDate() | Should -BeLessThan (Get-Date).AddDays(-59)
        }

        It 'matches excluded usernames, folder names, sids and paths' {
            $options = [CleanupOptions]::new(60, 500, 'C:\Users', @('TestUser', 'S-1-5-21-1'), @('C:\Users\Excluded'))

            $profile = [LocalProfileCandidate]::new()
            $profile.UserName = 'testuser'
            $profile.ProfileFolderName = 'TestUser'
            $profile.SID = 'S-1-5-21-999'
            $profile.LocalPath = 'C:\Users\TestUser'

            $options.IsExcluded($profile) | Should -BeTrue

            $profile2 = [LocalProfileCandidate]::new()
            $profile2.UserName = 'Another'
            $profile2.ProfileFolderName = 'Another'
            $profile2.SID = 'S-1-5-21-1'
            $profile2.LocalPath = 'C:\Users\Another'

            $options.IsExcluded($profile2) | Should -BeTrue

            $profile3 = [LocalProfileCandidate]::new()
            $profile3.UserName = 'Another'
            $profile3.ProfileFolderName = 'Another'
            $profile3.SID = 'S-1-5-21-2'
            $profile3.LocalPath = 'C:\Users\Excluded'

            $options.IsExcluded($profile3) | Should -BeTrue
        }

        It 'normalizes excluded profile paths' {
            $options = [CleanupOptions]::new(60, 500, 'C:\Users', @(), @('C:\Users\Public\'))
            $profile = [LocalProfileCandidate]::new()
            $profile.LocalPath = 'C:\Users\Public'

            $options.IsExcluded($profile) | Should -BeTrue
        }
    }

    Describe 'Helper functions' {
        It 'returns empty path values as-is' {
            Get-LocalUserDataRemoverNormalizedPath -Path '' | Should -Be ''
            Test-LocalUserDataRemoverPathUnderRoot -Path '' -Root 'C:\Users' | Should -BeFalse
        }

        It 'builds a default log path under the current location' {
            Push-Location $TestDrive
            try {
                $path = Get-LocalUserDataRemoverDefaultLogPath

                $path | Should -Match ([regex]::Escape((Join-Path -Path $TestDrive -ChildPath 'logs')))
                $path | Should -Match 'LocalUserDataRemover-\d{8}-\d{6}\.log$'
            } finally {
                Pop-Location
            }
        }

        It 'detects paths under the configured root' {
            Test-LocalUserDataRemoverPathUnderRoot -Path 'C:\Users\TestUser' -Root 'C:\Users' | Should -BeTrue
            Test-LocalUserDataRemoverPathUnderRoot -Path 'C:\Users' -Root 'C:\Users' | Should -BeTrue
            Test-LocalUserDataRemoverPathUnderRoot -Path 'C:\Windows\System32' -Root 'C:\Users' | Should -BeFalse
        }

        It 'converts CIM date strings and tolerates invalid input' {
            ConvertFrom-LocalUserDataRemoverCimDateTime -Value $null | Should -Be ([datetime]::MinValue)
            ConvertFrom-LocalUserDataRemoverCimDateTime -Value (Get-Date) | Should -BeOfType ([datetime])
            ConvertFrom-LocalUserDataRemoverCimDateTime -Value 'not-a-date' | Should -Be ([datetime]::MinValue)
        }

        It 'resolves account names from a local path when sid translation fails' {
            Resolve-LocalUserDataRemoverAccountName -Sid 'S-1-5-21-invalid' -LocalPath 'C:\Users\TestUser' | Should -Be 'TestUser'
            Resolve-LocalUserDataRemoverAccountName -Sid $null -LocalPath 'C:\Users\TestUser' | Should -Be 'TestUser'
            Resolve-LocalUserDataRemoverAccountName -Sid $null -LocalPath $null | Should -BeNullOrEmpty
        }

        It 'uses the Size property when available and falls back to folder scanning' {
            $profile = [pscustomobject]@{ Size = 12345 }

            Get-LocalProfileSizeBytes -ProfileInstance $profile -LocalPath 'C:\Users\TestUser' | Should -Be 12345

            Mock -CommandName Get-LocalUserDataRemoverFolderSizeBytes -MockWith { 67890 }
            $profile2 = [pscustomobject]@{ Size = 0 }

            Get-LocalProfileSizeBytes -ProfileInstance $profile2 -LocalPath 'C:\Users\TestUser' | Should -Be 67890
        }
    }

    Describe 'Test-LocalUserProfileCandidate' {
        It 'marks stale profiles for deletion' {
            $options = [CleanupOptions]::new(60, 500, 'C:\Users', @(), @())
            $profile = [LocalProfileCandidate]::new()
            $profile.UserName = 'TestUser'
            $profile.ProfileFolderName = 'TestUser'
            $profile.LocalPath = 'C:\Users\TestUser'
            $profile.LastUseTime = (Get-Date).AddDays(-90)
            $profile.SizeBytes = 10MB

            $decision = Test-LocalUserProfileCandidate -Profile $profile -Options $options

            $decision.ShouldDelete | Should -BeTrue
            $decision.IsOld | Should -BeTrue
            $decision.IsLarge | Should -BeFalse
        }

        It 'marks oversized profiles for deletion' {
            $options = [CleanupOptions]::new(60, 500, 'C:\Users', @(), @())
            $profile = [LocalProfileCandidate]::new()
            $profile.UserName = 'TestUser'
            $profile.ProfileFolderName = 'TestUser'
            $profile.LocalPath = 'C:\Users\TestUser'
            $profile.LastUseTime = (Get-Date).AddDays(-1)
            $profile.SizeBytes = [int64](600MB)

            $decision = Test-LocalUserProfileCandidate -Profile $profile -Options $options

            $decision.ShouldDelete | Should -BeTrue
            $decision.IsOld | Should -BeFalse
            $decision.IsLarge | Should -BeTrue
        }

        It 'skips loaded profiles' {
            $options = [CleanupOptions]::new(60, 500, 'C:\Users', @(), @())
            $profile = [LocalProfileCandidate]::new()
            $profile.UserName = 'TestUser'
            $profile.ProfileFolderName = 'TestUser'
            $profile.LocalPath = 'C:\Users\TestUser'
            $profile.LastUseTime = (Get-Date).AddDays(-90)
            $profile.SizeBytes = 10MB
            $profile.Loaded = $true

            $decision = Test-LocalUserProfileCandidate -Profile $profile -Options $options

            $decision.ShouldDelete | Should -BeFalse
            $decision.Reasons -join '; ' | Should -Match 'currently loaded'
        }

        It 'skips special profiles' {
            $options = [CleanupOptions]::new(60, 500, 'C:\Users', @(), @())
            $profile = [LocalProfileCandidate]::new()
            $profile.UserName = 'TestUser'
            $profile.ProfileFolderName = 'TestUser'
            $profile.LocalPath = 'C:\Users\TestUser'
            $profile.LastUseTime = (Get-Date).AddDays(-90)
            $profile.SizeBytes = 10MB
            $profile.Special = $true

            $decision = Test-LocalUserProfileCandidate -Profile $profile -Options $options

            $decision.ShouldDelete | Should -BeFalse
            $decision.Reasons -join '; ' | Should -Match 'Special profile'
        }

        It 'skips profiles outside the target root' {
            $options = [CleanupOptions]::new(60, 500, 'C:\Users', @(), @())
            $profile = [LocalProfileCandidate]::new()
            $profile.UserName = 'TestUser'
            $profile.ProfileFolderName = 'TestUser'
            $profile.LocalPath = 'D:\Profiles\TestUser'
            $profile.LastUseTime = (Get-Date).AddDays(-90)
            $profile.SizeBytes = 10MB

            $decision = Test-LocalUserProfileCandidate -Profile $profile -Options $options

            $decision.ShouldDelete | Should -BeFalse
            $decision.Reasons -join '; ' | Should -Match 'outside the target root'
        }

        It 'skips excluded profiles' {
            $options = [CleanupOptions]::new(60, 500, 'C:\Users', @('TestUser'), @())
            $profile = [LocalProfileCandidate]::new()
            $profile.UserName = 'TestUser'
            $profile.ProfileFolderName = 'TestUser'
            $profile.LocalPath = 'C:\Users\TestUser'
            $profile.LastUseTime = (Get-Date).AddDays(-90)
            $profile.SizeBytes = 10MB

            $decision = Test-LocalUserProfileCandidate -Profile $profile -Options $options

            $decision.ShouldDelete | Should -BeFalse
            $decision.Reasons -join '; ' | Should -Match 'excluded by policy'
        }

        It 'skips profiles that are neither old nor oversized' {
            $options = [CleanupOptions]::new(60, 500, 'C:\Users', @(), @())
            $profile = [LocalProfileCandidate]::new()
            $profile.UserName = 'TestUser'
            $profile.ProfileFolderName = 'TestUser'
            $profile.LocalPath = 'C:\Users\TestUser'
            $profile.LastUseTime = (Get-Date).AddDays(-1)
            $profile.SizeBytes = 10MB

            $decision = Test-LocalUserProfileCandidate -Profile $profile -Options $options

            $decision.ShouldDelete | Should -BeFalse
            $decision.Reasons -join '; ' | Should -Match 'age or size threshold'
        }
    }

    Describe 'Get-LocalUserProfileCandidates' {
        It 'maps CIM profile data and filters profiles outside the target root' {
            $inside = New-LocalUserDataRemoverProfileStub -Sid 'S-1-5-21-100' -LocalPath 'C:\Users\TestUser' -LastUseTime '20240422093000.000000+000' -Loaded:$true -Size 12345
            $outside = New-LocalUserDataRemoverProfileStub -Sid 'S-1-5-21-200' -LocalPath 'D:\Profiles\Other' -LastUseTime '20240422093000.000000+000' -Size 999

            Mock -CommandName Get-CimInstance -MockWith { @($inside, $outside) }

            $profiles = Get-LocalUserProfileCandidates -ProfileRoot 'C:\Users'

            $profiles.Count | Should -Be 1
            $profiles[0].SID | Should -Be 'S-1-5-21-100'
            $profiles[0].LocalPath | Should -Be 'C:\Users\TestUser'
            $profiles[0].ProfileFolderName | Should -Be 'TestUser'
            $profiles[0].UserName | Should -Be 'TestUser'
            $profiles[0].Loaded | Should -BeTrue
            $profiles[0].Special | Should -BeFalse
            $profiles[0].SizeBytes | Should -Be 12345
            $profiles[0].SourceInstance.SID | Should -Be 'S-1-5-21-100'
            $profiles[0].LastUseTime | Should -BeOfType ([datetime])
        }

        It 'falls back to folder size when the cim size is unavailable' {
            $profile = New-LocalUserDataRemoverProfileStub -Sid 'S-1-5-21-300' -LocalPath 'C:\Users\SizedByFolder' -LastUseTime '20240422093000.000000+000' -Size 0

            Mock -CommandName Get-CimInstance -MockWith { @($profile) }
            Mock -CommandName Get-LocalUserDataRemoverFolderSizeBytes -MockWith { 67890 }

            $profiles = Get-LocalUserProfileCandidates -ProfileRoot 'C:\Users'

            $profiles.Count | Should -Be 1
            $profiles[0].SizeBytes | Should -Be 67890
        }
    }

    Describe 'Write-LocalUserDataRemoverLog' {
        It 'writes a formatted line when a log path is configured' {
            $logPath = Join-Path -Path $TestDrive -ChildPath 'cleanup.log'

            $resolvedPath = Write-LocalUserDataRemoverLog -Message 'hello world' -LogPath $logPath -Level 'Summary'

            $resolvedPath | Should -Be $logPath

            $content = Get-Content -LiteralPath $logPath -Raw
            $content | Should -Match '\[SUMMARY\]'
            $content | Should -Match 'hello world'
        }

        It 'does nothing when no log path is configured' {
            { Write-LocalUserDataRemoverLog -Message 'ignored' -LogPath $null } | Should -Not -Throw
        }

        It 'resolves relative log paths against the current location' {
            Push-Location $TestDrive
            try {
                $resolvedPath = Write-LocalUserDataRemoverLog -Message 'relative path' -LogPath 'relative.log' -Level 'Info'

                $resolvedPath | Should -Be (Join-Path -Path $TestDrive -ChildPath 'relative.log')
                Test-Path -LiteralPath (Join-Path -Path $TestDrive -ChildPath 'relative.log') | Should -BeTrue
            } finally {
                Pop-Location
            }
        }
    }

    Describe 'Remove-LocalUserProfile' {
        It 'deletes a profile via the supplied CIM instance' {
            $profile = [LocalProfileCandidate]::new()
            $profile.SID = 'S-1-5-21-100'
            $profile.SourceInstance = New-LocalUserDataRemoverProfileStub -Sid $profile.SID -LocalPath 'C:\Users\TestUser'

            Remove-LocalUserProfile -Profile $profile | Should -BeTrue
        }

        It 'looks up the CIM instance by sid when needed' {
            $profile = [LocalProfileCandidate]::new()
            $profile.SID = 'S-1-5-21-200'

            Mock -CommandName Get-CimInstance -MockWith {
                New-LocalUserDataRemoverProfileStub -Sid $profile.SID -LocalPath 'C:\Users\ResolvedUser'
            }

            Remove-LocalUserProfile -Profile $profile | Should -BeTrue
            Assert-MockCalled Get-CimInstance -Times 1
        }

        It 'fails when neither sid nor cim instance exists' {
            $profile = [LocalProfileCandidate]::new()

            { Remove-LocalUserProfile -Profile $profile } | Should -Throw
        }
    }

    Describe 'Start-LocalUserDataRemoval' {
        It 'creates a log file automatically when no log path is provided' {
            Push-Location $TestDrive
            try {
                Mock -CommandName Get-LocalUserProfileCandidates -MockWith { @() }

                $result = Start-LocalUserDataRemoval -ProfileRoot 'C:\Users' -Confirm:$false

                $result.ScannedCount | Should -Be 0
                $logFiles = Get-ChildItem -Path (Join-Path -Path $TestDrive -ChildPath 'logs') -Filter '*.log'
                $logFiles.Count | Should -Be 1
                $logContent = Get-Content -LiteralPath $logFiles[0].FullName -Raw
                $logContent | Should -Match 'Starting scan'
                $logContent | Should -Match 'Finished scan'
            } finally {
                Pop-Location
            }
        }

        It 'deletes eligible profiles and writes the success log path' {
            $bothProfile = [LocalProfileCandidate]::new()
            $bothProfile.SID = 'S-1-5-21-300'
            $bothProfile.UserName = 'BothUser'
            $bothProfile.ProfileFolderName = 'BothUser'
            $bothProfile.LocalPath = 'C:\Users\BothUser'
            $bothProfile.LastUseTime = (Get-Date).AddDays(-120)
            $bothProfile.SizeBytes = 600MB

            $oldProfile = [LocalProfileCandidate]::new()
            $oldProfile.SID = 'S-1-5-21-301'
            $oldProfile.UserName = 'OldUser'
            $oldProfile.ProfileFolderName = 'OldUser'
            $oldProfile.LocalPath = 'C:\Users\OldUser'
            $oldProfile.LastUseTime = (Get-Date).AddDays(-120)
            $oldProfile.SizeBytes = 10MB

            $safeProfile = [LocalProfileCandidate]::new()
            $safeProfile.SID = 'S-1-5-21-302'
            $safeProfile.UserName = 'SafeUser'
            $safeProfile.ProfileFolderName = 'SafeUser'
            $safeProfile.LocalPath = 'C:\Users\SafeUser'
            $safeProfile.LastUseTime = (Get-Date).AddDays(-1)
            $safeProfile.SizeBytes = 10MB
            $logPath = Join-Path -Path $TestDrive -ChildPath 'run.log'

            Mock -CommandName Get-LocalUserProfileCandidates -MockWith { @($bothProfile, $oldProfile, $safeProfile) }
            Mock -CommandName Remove-LocalUserProfile -MockWith { $true }

            $result = Start-LocalUserDataRemoval -ProfileRoot 'C:\Users' -InactivityDays 60 -MaxProfileSizeMB 500 -LogPath $logPath -Confirm:$false

            $result.ScannedCount | Should -Be 3
            $result.DeletedCount | Should -Be 2
            $result.SkippedCount | Should -Be 1
            $result.FailedCount | Should -Be 0
            $result.DeletedProfiles.Count | Should -Be 2
            Assert-MockCalled Remove-LocalUserProfile -Times 2
            $logContent = Get-Content -LiteralPath $logPath -Raw
            $logContent | Should -Match 'Starting scan'
            $logContent | Should -Match 'Deleted profile'
            $logContent | Should -Match 'Finished scan'
        }

        It 'scans, deletes, skips and reports totals' {
            $oldProfile = [LocalProfileCandidate]::new()
            $oldProfile.UserName = 'OldUser'
            $oldProfile.ProfileFolderName = 'OldUser'
            $oldProfile.LocalPath = 'C:\Users\OldUser'
            $oldProfile.LastUseTime = (Get-Date).AddDays(-90)
            $oldProfile.SizeBytes = 10MB

            $bigProfile = [LocalProfileCandidate]::new()
            $bigProfile.UserName = 'BigUser'
            $bigProfile.ProfileFolderName = 'BigUser'
            $bigProfile.LocalPath = 'C:\Users\BigUser'
            $bigProfile.LastUseTime = (Get-Date).AddDays(-1)
            $bigProfile.SizeBytes = 600MB

            $safeProfile = [LocalProfileCandidate]::new()
            $safeProfile.UserName = 'SafeUser'
            $safeProfile.ProfileFolderName = 'SafeUser'
            $safeProfile.LocalPath = 'C:\Users\SafeUser'
            $safeProfile.LastUseTime = (Get-Date).AddDays(-1)
            $safeProfile.SizeBytes = 10MB

            Mock -CommandName Get-LocalUserProfileCandidates -MockWith {
                @($oldProfile, $bigProfile, $safeProfile)
            }

            Mock -CommandName Remove-LocalUserProfile -MockWith { $true }

            $result = Start-LocalUserDataRemoval -ProfileRoot 'C:\Users' -InactivityDays 60 -MaxProfileSizeMB 500 -WhatIf

            $result.ScannedCount | Should -Be 3
            $result.DeletedCount | Should -Be 0
            $result.SkippedCount | Should -Be 3
            $result.FailedCount | Should -Be 0
            $result.SkippedProfiles.Count | Should -Be 3
            Assert-MockCalled Remove-LocalUserProfile -Times 0
        }

        It 'reports delete failures without stopping the batch' {
            $badProfile = [LocalProfileCandidate]::new()
            $badProfile.UserName = 'BadUser'
            $badProfile.ProfileFolderName = 'BadUser'
            $badProfile.LocalPath = 'C:\Users\BadUser'
            $badProfile.LastUseTime = (Get-Date).AddDays(-90)
            $badProfile.SizeBytes = 10MB

            Mock -CommandName Get-LocalUserProfileCandidates -MockWith { @($badProfile) }
            Mock -CommandName Remove-LocalUserProfile -MockWith { throw 'delete failed' }

            $result = Start-LocalUserDataRemoval -ProfileRoot 'C:\Users' -InactivityDays 60 -MaxProfileSizeMB 500 -Confirm:$false

            $result.ScannedCount | Should -Be 1
            $result.DeletedCount | Should -Be 0
            $result.FailedCount | Should -Be 1
            $result.FailedProfiles[0].Error | Should -Match 'delete failed'
        }
    }
}

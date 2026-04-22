$modulePath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') -ChildPath 'LocalUserDataRemover.psd1'
Import-Module $modulePath -Force

InModuleScope LocalUserDataRemover {
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

    Describe 'Remove-LocalUserProfile' {
        It 'deletes a profile via the supplied CIM instance' {
            $profile = [LocalProfileCandidate]::new()
            $profile.SID = 'S-1-5-21-100'
            $profile.SourceInstance = [pscustomobject]@{ SID = $profile.SID }
            $profile.SourceInstance | Add-Member -MemberType ScriptMethod -Name Delete -Value { [pscustomobject]@{ ReturnValue = 0 } } -Force

            Remove-LocalUserProfile -Profile $profile | Should -BeTrue
        }

        It 'looks up the CIM instance by sid when needed' {
            $profile = [LocalProfileCandidate]::new()
            $profile.SID = 'S-1-5-21-200'

            Mock -CommandName Get-CimInstance -MockWith {
                $obj = [pscustomobject]@{ SID = $profile.SID }
                $obj | Add-Member -MemberType ScriptMethod -Name Delete -Value { [pscustomobject]@{ ReturnValue = 0 } } -Force
                return $obj
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

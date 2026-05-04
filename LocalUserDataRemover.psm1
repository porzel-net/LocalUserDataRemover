$moduleRoot = $PSScriptRoot

. (Join-Path -Path $moduleRoot -ChildPath 'Classes/Domain/LocalProfileCandidate.ps1')
. (Join-Path -Path $moduleRoot -ChildPath 'Classes/Domain/CleanupOptions.ps1')
. (Join-Path -Path $moduleRoot -ChildPath 'Classes/Domain/CleanupResult.ps1')

. (Join-Path -Path $moduleRoot -ChildPath 'Private/LocalUserDataRemover.Helpers.ps1')
. (Join-Path -Path $moduleRoot -ChildPath 'Private/Get-LocalUserProfileCandidates.ps1')
. (Join-Path -Path $moduleRoot -ChildPath 'Private/Test-LocalUserProfileCandidate.ps1')
. (Join-Path -Path $moduleRoot -ChildPath 'Private/Remove-LocalUserProfile.ps1')
. (Join-Path -Path $moduleRoot -ChildPath 'Private/Write-LocalUserDataRemoverLog.ps1')

. (Join-Path -Path $moduleRoot -ChildPath 'Public/Start-LocalUserDataRemoval.ps1')
. (Join-Path -Path $moduleRoot -ChildPath 'Public/Remove-LocalUserProfileAndAccount.ps1')

Export-ModuleMember -Function 'Start-LocalUserDataRemoval', 'Remove-LocalUserProfileAndAccount'

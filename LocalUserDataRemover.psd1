@{
    RootModule        = 'LocalUserDataRemover.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b7f6d9a3-6d28-47f4-9d0a-f4f1b5f77f12'
    Author            = 'OpenAI Codex'
    CompanyName       = 'OpenAI'
    Copyright         = '(c) OpenAI. All rights reserved.'
    Description       = 'PowerShell 5.1 cleanup for stale or oversized local user profiles.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Start-LocalUserDataRemoval', 'Remove-LocalUserProfileAndAccount')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('PowerShell', 'Windows', 'Profiles', 'Cleanup')
        }
    }
}

# LocalUserDataRemover

`LocalUserDataRemover` is a small Windows PowerShell 5.1 module for cleaning up local user profiles on Windows 10 systems.

It is designed for environments where users log on with domain accounts, but their local profile data on the machine should be removed when it is no longer needed.

## What It Does

The module scans `C:\Users` and removes local user profiles when one of these conditions is met:

- the profile has not been used for `60` days or more
- the profile uses more than `500 MB`

Profiles are only removed through the Windows profile management API, not by deleting folders directly.

## Safety Rules

The cleanup logic intentionally avoids removing profiles that are likely in active use or are system-managed:

- loaded profiles are skipped
- special profiles are skipped
- the root folder is restricted to `C:\Users` by default
- known built-in profile names are excluded by default
- the command supports `-WhatIf` and `-Confirm`

This means a user can log in again after the profile has been removed. The account itself is not deleted.

For a kiosk, download station, or similar shared machine, there is a separate command that deletes a named local user account and its profile in one step.

## Project Layout

- [LocalUserDataRemover.psd1](./LocalUserDataRemover.psd1)
  - module manifest
- [LocalUserDataRemover.psm1](./LocalUserDataRemover.psm1)
  - module entry point
- [Public/Start-LocalUserDataRemoval.ps1](./Public/Start-LocalUserDataRemoval.ps1)
  - public command
- [Classes/Domain](./Classes/Domain)
  - rules and data objects
- [Private](./Private)
  - helper and infrastructure functions
- [Tests](./Tests)
  - Pester tests

The structure is intentionally small and follows the same clean split used in the larger PowerShell project you referenced, but without the extra layers that are not needed here.

## Requirements

- Windows PowerShell `5.1`
- Windows 10 or newer
- permission to enumerate and remove local profiles

The module uses:

- `Win32_UserProfile`
- `Get-CimInstance`
- `Invoke-CimMethod`

## Usage

Load the module:

```powershell
Import-Module .\LocalUserDataRemover.psd1 -Force
```

Run a dry run first:

```powershell
Start-LocalUserDataRemoval -WhatIf
```

Run with the default thresholds:

```powershell
Start-LocalUserDataRemoval
```

Run with custom thresholds:

```powershell
Start-LocalUserDataRemoval -InactivityDays 45 -MaxProfileSizeMB 750
```

Delete one named local user and its profile:

```powershell
Remove-LocalUserProfileAndAccount -LocalUserName 'DownloadStationUser' -WhatIf
Remove-LocalUserProfileAndAccount -LocalUserName 'DownloadStationUser'
```

Write a log file:

```powershell
Start-LocalUserDataRemoval -LogPath C:\logs\LocalUserDataRemover.log -WhatIf
```

If you do not pass `-LogPath`, the module automatically writes to a local `logs` folder in the current working directory, for example:

- `.\logs\LocalUserDataRemover-20260504-164500.log`

## Parameters

- `-InactivityDays`
  - default: `60`
  - a profile is eligible when the last use is older than this value
- `-MaxProfileSizeMB`
  - default: `500`
  - a profile is eligible when it is larger than this value
- `-ProfileRoot`
  - default: `C:\Users`
  - only profiles below this path are considered
- `-ExcludeUserName`
  - user names, folder names, or SIDs that should never be removed
- `-ExcludeProfilePath`
  - full paths that should never be removed
- `-LogPath`
  - optional log file path

### `Remove-LocalUserProfileAndAccount`

- `-LocalUserName`
  - the local Windows account name to remove
- `-ProfileRoot`
  - default: `C:\Users`
  - used to find the profile to delete
- `-LogPath`
  - optional log file path

This command resolves the local account with `Get-LocalUser`, deletes the matching `Win32_UserProfile`, and then removes the local account with `Remove-LocalUser`.

## Output

The command returns a structured result object with:

- scanned profile count
- deleted profile count
- skipped profile count
- failed profile count
- lists of deleted, skipped, and failed profiles

## Tests

The repository includes Pester tests for:

- threshold logic
- exclusion rules
- helper functions
- delete-path behavior
- batch orchestration

Run them from the project folder with your PowerShell 5.1 environment and Pester installed.

## Important Notes

- This script only removes local profile data.
- It does not remove the AD account.
- It does not delete a local Windows account unless you call `Remove-LocalUserProfileAndAccount`.
- If the user logs in again later, Windows can recreate the profile.
- Always use `-WhatIf` first on a real machine.

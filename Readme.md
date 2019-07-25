# UpdateSPODomainGroup

This is a PowerShell Script to update the displayname and e-mail address of security group (domain group) of SharePoint Online site collection.

## Example1

.\UpdateSPODomainGroup.ps1 -adminurl https://tenant-admin.sharpoint.com -GroupName MyGroup

## Example2
If the Tenant Admin does not have permission to open the site collection. Please specify -force $true, so that the user can have temporal access to site collection while executing this PowerShell.

.\UpdateSPODomainGroup.ps1 -adminurl https://tenant-admin.sharpoint.com -GroupName MyGroup -force $true


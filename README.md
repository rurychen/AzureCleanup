When using Azure as your development platform, you eventually find yourself deleting resources 1 by 1 or entire resource groups.
Cause when you delete a VM in ARM (the new portal), it deletes only the VM, but leaves the VHD, the NIC, the public IP, and NGS’s.
so what if you could run a script that looks at the unused resources and deletes them for you?

The script is available and requires AzureRM PowerShell 5.0.0.


For your safety the script has some features built in that ensure that you don’t delete everything at once in fact, the default mode is to scan only. and not delete.



Steps 1. Install AzureRM PowerShell 5.0.0.
https://docs.microsoft.com/en-us/powershell/azure/install-azurerm-ps?view=azurermps-5.0.0
# Install the Azure Resource Manager modules from the PowerShell Gallery
Install-Module AzureRM -AllowClobber

Some times it failed with  "gives error Install-Module A parameter cannot be found that matches parameter name AllowClobber".

Note that AllowClobber is only available on PS 5  and later.
We could try this.
find-module azurerm | Install-Module

Steps 2. Load the AzureRM module

Import-Module AzureRM

Steps 3. Checking the version of Azure PowerShell
Get-Module AzureRM -list | Select-Object Name,Version,Path


Step 4. Download the script AzureCleanup.ps1 , and run following command in the PowerShell console.
.\AzureCleanup-v3.ps1 -Mode Full


<#
.SYNOPSIS
    .
.DESCRIPTION
    .
.PARAMETER Mode
    Please select a scanning mode, which can be either Full, Storage or Network.
    
.PARAMETER ProductionRun
    Default is $false, nothing will be deleted. 
    Set to $True, will delete the resouce. Specifies is you want to run in production mode, which will actually delete the 
	resources found to be redundant. For some resources additional confirmation will be required
    
.PARAMETER YesToAll
    Set to $true will skip all Confirm Box.
    
 .PARAMETER Login
    Default is $false, open a login box to Azure. Change to $Ture, will use the current Login session.
    
  .PARAMETER Log
    Set to $true  will genreate to log file for review.
    
.EXAMPLE
    C:\PS>AzureCleanUp.ps1 -Mode Full -ProductionRun $false 
    <Description of example>
.NOTES
    Original Author: Roelf Zomerman 
    Change by Rury Chen:
    .\AzureCleanup-v3.ps1 -Mode Full -ProductionRun $false -Login $true -Log $true -YesToAll $true
    Date: 2017-12-7
#>
[CmdletBinding(DefaultParameterSetName = "Mode")]
param(
  [Parameter(
    Mandatory = $true,
    ParameterSetName = "Mode",
    ValueFromPipeline = $true,
    ValueFromPipelineByPropertyName = $true,
    HelpMessage = "Select the Mode"
  )]
  [ValidateNotNullOrEmpty()]
  [string[]]
  [Alias('Please provide the Mode')]
  $Mode,#Mode
  [Parameter(
    Mandatory = $false
  )]
  $ProductionRun,
  [Parameter(
    Mandatory = $false
  )]
  $Login,
  [Parameter(
    Mandatory = $false
  )]
  $YesToAll,
  [Parameter(
    Mandatory = $false
  )]
  $Log
)
# Add the Resouce name to here, all resouces start with following name will be ignore
$SkipResouceNameList = (
   "TEST_SKIP",
)


function isNotSkip ($name) {
  foreach ($temp in $SkipResource) {

    if ($name.ToLower().StartsWith($temp)) {
      Write-Host (" Skip to delete (Edit SkipResouceNameList to remove this skip action) :" + $name) -ForegroundColor Red
      WriteDebug (" Skip to delete (Edit SkipResouceNameList to remove this skip action) : " + $name)
      return $false;
    }

  }
  return $true;
}
function ActivateDebug () {
  Add-Content -Path $LogfileActivated -Value "***************************************************************************************************"
  Add-Content -Path $LogfileActivated -Value "Started processing at [$([DateTime]::Now)]."
  Add-Content -Path $LogfileActivated -Value "***************************************************************************************************"
  Add-Content -Path $LogfileActivated -Value ""
  Write-Host "Debug Enabled writing to logfile: " $LogfileActivated
}


function WriteDebug {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)] [string]$LineValue)
  process {
    Add-Content -Path $LogfileActivated -Value $LineValue
  }
}


function GetAllVMProperties () {
  #GetAllVM's
  $AllVMs = Get-AzureRmVM
  Write-Host (" found " + $AllVMs.Count + ": ") -ForegroundColor Gray -NoNewline
  WriteDebug (" found " + $AllVMs.Count + ": ")
  foreach ($VM in $AllVMs) {
    Write-Host ($VM.Name + ",") -ForegroundColor Gray -NoNewline
    WriteDebug ($VM.Name + ",")
    $VMNames.Add($VM.Name) > $null
    if ($vm.DiagnosticsProfile.BootDiagnostics.Enabled -eq $true) {
      $VMDiagStorageURL.Add($vm.DiagnosticsProfile.BootDiagnostics.StorageUri) > $null
      WriteDebug $VM.Name
      WriteDebug (" BootDiagnostics " + $vm.DiagnosticsProfile.BootDiagnostics.StorageUri)
    }
    $OSDisk = $VM.StorageProfile.OsDisk
    WriteDebug (" OS Disk " + $OSDisk.vhd.uri)
    $DiskURIArray.Add($OSDisk.vhd.uri) > $null
    $DataDisks = New-Object System.Collections.ArrayList
    $DataDisks = $VM.StorageProfile.DataDisks

    foreach ($dDisk in $DataDisks) {
      #Write-Host $dDisk.vhd.uri -ForegroundColor Gray
      WriteDebug (" Data Disk " + $dDisk.vhd.uri)
      $DiskURIArray.Add($dDisk.vhd.uri) > $null
    }
    #NEED TO GET ALL NETWORK ADAPTERS
    $NICIDs = $VM.NetworkInterfaceIDs
    foreach ($nicID in $NICIDs) {
      $VMNICArray.Add($nicID) > $null
      #Write-Host $nicID -ForegroundColor Gray
      WriteDebug (" NIC " + $nicID)
    }
  }
}


function PrepareDeleteStorageAccountContents () {
  $StorageAccounts = Get-AzureRmStorageAccount
  Write-Host (" found " + $StorageAccounts.Count + " accounts") -ForegroundColor Gray
  WriteDebug (" found " + $StorageAccounts.Count + " accounts")
  #Validate StorageAccount URL in VMDriveArray
  foreach ($SA in $StorageAccounts) {
    #Need to skip the built in security data logging part..  
    if ($SA.ResourceGroupName -eq 'securitydata') { continue }
    Write-Host ("Storage Account " + $SA.StorageAccountName) -ForegroundColor Cyan
    WriteDebug (" Storage Account " + $SA.StorageAccountName)
    $DeleteStorageAccount = $True #SET THE DELETE FLAG TO YES (WILL BE OVERRIDDEN IF BLOCKED)

    #RESET PER STORAGE ACCOUNT
    $FileDeleteCounter = 0
    $DeleteContainers = $null
    $DeleteFiles = $null
    $DeleteContainerValidationCounter = 0
    $DeleteFiles = New-Object System.Collections.ArrayList
    $DeleteContainers = New-Object System.Collections.ArrayList


    if ($DiskURIArray -match $SA.StorageAccountName -or $VMDiagStorageURL -match $SA.StorageAccountName) {
      #IF THE STORAGE ACCOUNTNAME IS BEING USED IN VM DISKS OR DIAGNOSTICS!
      $count = $SA.StorageAccountName.Length
      $msg = " is being used by VM's. Continuing with file scanning but storage account deletion is DISABLED"
      WriteDebug "Storage Account Blocked from deletion, existing VM's found"
      WriteDebug (" option1: " + $VMDiagStorageURL + " " + $SA.StorageAccountName)
      WriteDebug (" option2: " + $DiskURIArray + " " + $SA.StorageAccountName)
      Write-Host ("!" * ($count + $msg.Length)) -ForegroundColor Magenta
      Write-Host ($SA.StorageAccountName + $msg) -ForegroundColor Yellow
      Write-Host ("!" * ($count + $msg.Length)) -ForegroundColor Magenta
      $DeleteStorageAccount = $False #MUST NOT DELETE STORAGE ACCOUNT
      Write-Host ""
    }
    else {
      Write-Host ("Storage Account " + $SA.StorageAccountName + " not being used by VM's") -ForegroundColor Green
      WriteDebug ("Nothing found on " + $SA.StorageAccountName)
      WriteDebug "DeleteStorageAccount Set to TRUE"
      $DeleteStorageAccount = $True
    }

    $Key = (Get-AzureRmStorageAccountKey -ResourceGroupName $SA.ResourceGroupName -Name $SA.StorageAccountName)
    $key1 = $ket.key1
    WriteDebug (" Storage Account Key default: " + $key1)
    if ($Key1 -eq $null) {
      #Different version of Powershell CMD'lets
      $key1 = $key.value[0]
      WriteDebug (" Storage Account Key 2nd attempt: " + $key1)
    }

    $SACtx = New-AzureStorageContext -StorageAccountName $SA.StorageAccountName -StorageAccountKey $Key1
    Write-Host (" Storage Context is " + $SACtx.StorageAccountName) -ForegroundColor Gray
    WriteDebug ("Storage Context set to: " + $SACtx.StorageAccountName)

    #STANDARD STORAGE
    if ($SA.AccountType -match 'Standard') {
      WriteDebug (" Standard Storage Account found, checking tables and queues")
      #THIS IS FOR TABLES AND QUEUES IF STORAGE IS STANDARD
      $Tables = Get-AzureStorageTable -Context $SACtx
      $queues = Get-AzureStorageQueue -Context $SACtx
      if (!($Tables)) {
        Write-Host " Storage Tables not found" -ForegroundColor Green
        WriteDebug (" SA deletion is " + $DeleteStorageAccount)
      }
      elseif ($Tables) {
        Write-Host " Storage Tables Found!" -ForegroundColor Yellow
        $DeleteStorageAccount = $False
        WriteDebug " Tables found, SA deletion set to FALSE"
      }

      if (!($queues)) {
        Write-Host " Storage Queues not found" -ForegroundColor Green
        WriteDebug (" SA deletion is " + $DeleteStorageAccount)
      }
      else {
        Write-Host " Storage Queues Found" -ForegroundColor Yellow
        $DeleteStorageAccount = $False
        WriteDebug " Queues found, SA deletion set to FALSE"
      }

      Write-Host ""
    } #STANDARD

    #THIS IS FOR BLOBS
    #GOING DOWN TO CONTAINER LEVEL
    $Containers = Get-AzureStorageContainer -Context $SACtx
    WriteDebug " scannnig containers"
    foreach ($contain in $Containers) {
      #RESET THE COUNTERS PER CONTAINER
      $DeleteFilesCheck = $null
      $DeleteFiles = $null
      $DeleteFiles = New-Object System.Collections.ArrayList
      $DeleteFilesCheck = New-Object System.Collections.ArrayList
      $DeleteContainer = $False #Security
      Write-Host (" Current container: " + $contain.Name) -ForegroundColor Green
      WriteDebug (" Current container: " + $contain.Name)

      #NEED TO FILTER OUT THE STILL BEING USED DIAGNOSTICS CONTAINERS
      $TempName = $contain.Name.split("-")[0]
      $TempName2 = $contain.Name.split("-")[1]
      if ($TempName -eq 'bootdiagnostics' -and $VMNames -match $TempName2.ToUpper()) {
        Write-Host "  container in use for VM diagnostics" -ForegroundColor Yellow
        WriteDebug "  container in use for VM diagnostics"
        WriteDebug "  BootDiagnostics found, SA deletion set to FALSE"
        $DeleteStorageAccount = $False
        continue
      }
      # Need to add additional security for insights-logs-networksecuritygroupflowevent (NetworkWatcher)
      if ($contain.Name -eq 'insights-logs-networksecuritygroupflowevent' -or $contain.Name -eq 'insights-logs-networksecuritygroupevent' -or $contain.Name -eq 'insights-logs-networksecuritygrouprulecounter') {
        Write-Host "  container in use for Network Insights" -ForegroundColor Yellow
        WriteDebug "  container in use for Network Insights"
        WriteDebug "  Other Services using SA, deletion set to FALSE"
        $DeleteStorageAccount = $False
        continue
      }

      $filesInContainer = Get-AzureStorageBlob -Container $contain.Name -Context $SACtx
      $FileDeleteCounter = 0
      if ($filesInContainer -eq $null) {
        $DeleteContainerValidationCounter++
        Write-Host " No files found" -ForegroundColor Yellow
        #DO YOU WISH TO DELETE THE Container?

        $result = 1
        if ($YesToAll) {
          $result = 0
        } else {

          $title = ""
          $message = "  Container: '" + $contain.Name + "' does not contain any files, would you like to delete it?"
          $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes",`
             "Marks container for deletion"
          $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No",`
             "Skips deletion"
          $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)
          $result = $host.ui.PromptForChoice($title,$message,$options,1)

        }
        switch ($result) {
          0 {
            Write-Host ($contain.Name + " marked for deletion") -ForegroundColor Yellow
            $DeleteContainers.Add($contain.Name) > $null
            WriteDebug "  no files in container, marked for deletion"
          }
          1 {
            Write-Host ($contain.Name + " will remain") -ForegroundColor Green
            $DeleteStorageAccount = $False
            WriteDebug "  no files in container, SKIPPED for deletion"
            WriteDebug "  SA deletion set to FALSE"
          }
        }
        continue
      }

      #GOING DOWN TO FILE LEVEL
      foreach ($file in $filesInContainer) {
        $SafeGuard = $FileDeleteCounter
        #NEED TO VALIDATE ON HTTP/HTTPS
        $BuiltVMFileName = ("https://" + $SA.StorageAccountName + ".blob.core.windows.net/" + $contain.Name + "/" + $file.Name)
        $BuiltVMFileName2 = ("http://" + $SA.StorageAccountName + ".blob.core.windows.net/" + $contain.Name + "/" + $file.Name)
        WriteDebug " scannig VM files in container"
        WriteDebug ("$BuiltVMFileName")

        #VALIDATE IF NOT IN USE BY VM
        if ($DiskURIArray -contains $BuiltVMFileName -or $DiskURIArray -contains $BuiltVMFileName2) {
          Write-Host (" " + $file.Name + " matches VM HDD file, and therefore must remain") -ForegroundColor Gray
          WriteDebug (" validated against DiskURIArray")
          continue
        }
        elseif ($VMNames -match $file.Name.split(".")[0] -and $file.Name.Endswith(".status") -eq $true) {
          Write-Host (" Existing VM status file for: " + $file.Name.split(".")[0]) -ForegroundColor Gray
          WriteDebug " statusfile check"
          WriteDebug (" option 1: " + $file.Name.split(".")[0] + " in VMNames")
          WriteDebug " and ends with .status"
          continue
        }
        else {
          WriteDebug ("file was not found in arrays:" + $file.Name)
          #DO YOU WISH TO DELETE THE FILE?
          $result = 1
          if ($YesToAll) {
            $result = 0
          } else {

            $title = ""
            $message = "  Delete: " + $file.Name
            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes",`
               "Marks file for deletion"
            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No",`
               "Skips deletion"
            $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)
            $result = $host.ui.PromptForChoice($title,$message,$options,1)
          }

          switch ($result) {
            0 {
              Write-Host ($file.Name + " marked for deletion") -ForegroundColor Yellow
              $DeleteFilesCheck.Add($file.Name + "*" + $contain.Name) > $null
              WriteDebug (" file: " + $file.Name + " added to deletion queue")
              $FileDeleteCounter++
            }
            1 {
              Write-Host ($file.Name + " will remain") -ForegroundColor Green
              WriteDebug (" keeping file: " + $file.Name)
              $DeleteStorageAccount = $False
            }
          }

        } #end else
      } # per file

      #Count the number of files marked for deletion versus the number of files in the container, then clear for container delete
      if ($FileDeleteCounter -eq $filesInContainer.Count) {
        WriteDebug (" FileDeleteCounter equals filesInContainer")
        WriteDebug (" 1: " + $FileDeleteCounter)
        WriteDebug (" 2: " + $filesInContainer.Count)
        Write-Host " Container marked for deletion" -ForegroundColor Red
        $FileDeleteCounter = $SafeGuard #NO INDIVIDUAL FILE DELETES REQUIRED reset to container start
        $DeleteContainerValidationCounter++
        $DeleteContainers.Add($contain.Name) > $null
        WriteDebug (" container: " + $contain.Name + " added to deletion queue")
        $DeleteFilesCheck.Clear()
        WriteDebug (" individual file deletion queue emptied")
      }
      elseif ($FileDeleteCounter -lt $filesInContainer.Count) {
        #The number of the to be deleted files is less than the amount of files in the container, merge the Arrays into 1 big one
        Write-Host " container not empty, retaining..." -ForegroundColor Green
        WriteDebug " container stays, individual file removal process..."
        $DeleteFiles = $DeleteFiles + $DeleteFilesCheck
      }
    } #ALL CONTAINERS DONE

    Write-Host ""
    Write-Host ("-" * 44) -ForegroundColor Green
    Write-Host ("Summary for " + $SA.StorageAccountName)
    Write-Host ("Delete StorageAccount ") -NoNewline
    Write-Host $DeleteStorageAccount -ForegroundColor Yellow
    Write-Host "Number of containers to be deleted: " -NoNewline
    Write-Host $DeleteContainers.Count -ForegroundColor Red
    Write-Host "Number of individual files to be deleted: " -NoNewline
    Write-Host $DeleteFiles.Count -ForegroundColor Red
    Write-Host ("-" * 44) -ForegroundColor Green

    if ($DeleteContainerValidationCounter -eq $Containers.Count -and $DeleteStorageAccount -eq $True) {

      if (isNotSkip $SA.StorageAccountName) {
        #STORAGE ACCOUNT DELETION
        Write-Host ("DELETING STORAGE ACCOUNT " + $SA.StorageAccountName) -ForegroundColor Yellow
        WriteDebug (" Storage Account Deletion due to:")
        WriteDebug (" Container validation" + $DeleteContainerValidationCounter)
        WriteDebug (" containers to be deleted: " + $Containers.Count)
        WriteDebug (" DeleteStorageAccount is TRUE")
        DeleteStorageAccount $SA $SACtx
      }
    }
    elseif ($DeleteContainerValidationCounter -eq $Containers.Count -and $DeleteContainers.Count -ne 0 -and $DeleteStorageAccount -eq $False) {
      #STORAGEACCOUNT DELETION IS BLOCKED BY QUEUES/TABLES, BUT PROCESSED CONTAINERS CAN BE REMOVED
      Write-Host ("DELETING CONTAINERS ") -ForegroundColor Yellow
      WriteDebug (" Container Deletion due to:")
      WriteDebug (" Container validation" + $DeleteContainerValidationCounter)
      WriteDebug (" containers to be deleted: " + $Containers.Count)
      WriteDebug (" DeleteStorageAccount is FALSE")
      DeleteContainer $SA.StorageAccountName $DeleteContainers $SACtx
    }
    elseif ($DeleteContainerValidationCounter -ne $Containers.Count -and $DeleteContainers.Count -ne 0) {
      #INDIVIDUAL CONTAINERS CAN BE REMOVED
      Write-Host ("DELETING CONTAINERS ") -ForegroundColor Yellow
      WriteDebug (" Container Deletion due to:")
      WriteDebug (" Container validation" + $DeleteContainerValidationCounter)
      WriteDebug (" containers to be deleted: " + $Containers.Count)
      WriteDebug (" number mismatch, therefore processing containers only")
      DeleteContainer $SA.StorageAccountName $DeleteContainers $SACtx
    }
    elseif ($DeleteContainer -eq $False -and $DeleteFiles.Count -gt 0) {
      #ONLY FILES CAN BE REMOVED
      Write-Host ("DELETING Individual Files") -ForegroundColor Yellow
      WriteDebug (" File Deletion due to:")
      WriteDebug (" Delete Container is FALSE")
      DeleteFiles $SA.StorageAccountName $DeleteFiles $SACtx
    }
    else {
      #Nothing to be deleted
      Write-Host ("Nothing to be deleted") -ForegroundColor Green
      WriteDebug " Nothing to be processed, no deletes"
      Write-Host ""
    }
  } #Next STORAGE ACCOUNT
}



function DeleteFiles ($StorageAccountIN,[array]$FilesArrayIN,$ContextIN) {
  Write-Host ($StorageAccountIN + " cannot be deleted")
  Write-Host "deleting the following files as marked"
  foreach ($file in $FilesArrayIN) {
    $FileSplitted = $file.split('*')
    if (isNotSkip $FileSplitted) {
      Write-Host (" " + $FileSplitted[0] + " in container" + $FileSplitted[1] + " to be deleted") -ForegroundColor Red
      $DeletedFiles.Add($file) > null
      if ($ProductionRun -eq $true) { Remove-AzureStorageBlob -Force -blob $FileSplitted[0] -Container $FileSplitted[1] -Context $ContextIN }
      else {
        Write-Host " (Test Run) Please be aware that during production run there is" -ForegroundColor Green -NoNewline
        Write-Host " NO " -ForegroundColor Yellow -NoNewline
        Write-Host "delete confirmation" -ForegroundColor Green
      }
    }
  }
  Write-Host ""
}


function DeleteContainer ($StorageAccountIN,[array]$ContainerIN,$ContextIN) {
  Write-Host "deleting the following containers"
  foreach ($co in $ContainerIN) {
    Write-Host (" Container named: " + $co + " to be deleted") -ForegroundColor Red
    $DeletedContainers.Add($co) > null
    if ($ProductionRun -eq $true) { Remove-AzureStorageContainer -Force -Name $co -Context $ContextIN }
    else {
      Write-Host " (Test Run) Please be aware that during production run there is" -ForegroundColor Green -NoNewline
      Write-Host " NO " -ForegroundColor Yellow -NoNewline
      Write-Host "delete confirmation" -ForegroundColor Green
    }
  }
  Write-Host ""
}

function DeleteStorageAccount {

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'high')]
  param($StorageAccountIN,$ContextIN)

  if ($YesToAll) {
    Write-Host "-------YesToAll--------" -ForegroundColor Yellow
    Write-Host ("deleting Storage Account: " + $StorageAccountIN.StorageAccountName) -ForegroundColor Red
    $DeletedStorageAccounts.Add($StorageAccountIN.StorageAccountName) > null
    if ($ProductionRun -eq $true) {
      Remove-AzureRmStorageAccount -Force -Name $StorageAccountIN.StorageAccountName -ResourceGroup $StorageAccountIN.ResourceGroupName
    } #WHATIFDOESNOTEXIST
    else { Write-Host " (Test Run) nothing deleted" -ForegroundColor Green }

  } else {


    process {
      if ($PSCmdlet.ShouldProcess($StorageAccountIN.StorageAccountName)) {
        Write-Host "---------------" -ForegroundColor Yellow
        Write-Host ("deleting Storage Account: " + $StorageAccountIN.StorageAccountName) -ForegroundColor Red
        $DeletedStorageAccounts.Add($StorageAccountIN.StorageAccountName) > null
        if ($ProductionRun -eq $true) {
          Remove-AzureRmStorageAccount -Force -Name $StorageAccountIN.StorageAccountName -ResourceGroup $StorageAccountIN.ResourceGroupName
        } #WHATIFDOESNOTEXIST
        else { Write-Host " (Test Run) nothing deleted" -ForegroundColor Green }
      }
      else {
        Write-Host (" Deletion NOT confirmed, not deleting storage account: " + $StorageAccountIN.StorageAccountName) -ForegroundColor Green
      }
    }

  }
}

function DeleteNIC ($NICIN) {
  if (isNotSkip $NICIN.Name) {
    Write-Host ("   will delete NIC: " + $NICIN.Name) -ForegroundColor Red
    Write-Host ("   in resource group: " + $NICIN.ResourceGroupName) -ForegroundColor Red
    $DeletedNICs.Add($NICIN.Name) > null
    if ($ProductionRun -eq $true) { Remove-AzureRmNetworkInterface -Force -Name $NICIN.Name -ResourceGroupName $NICIN.ResourceGroupName }
    else {
      Write-Host " (Test Run) Please be aware that during production run there is" -ForegroundColor Green -NoNewline
      Write-Host " NO " -ForegroundColor Yellow -NoNewline
      Write-Host "delete confirmation" -ForegroundColor Green
    }

  }
}

function DeletePublicIPAddress ($PublicIPIN) {
  if (isNotSkip $PublicIPIN.Name) {
    Write-Host ("   will delete Public IP: " + $PublicIPIN.Name) -ForegroundColor Red
    Write-Host ("   in resource group: " + $PublicIPIN.ResourceGroupName) -ForegroundColor Red
    $DeletedPublicIPAddresses.Add($PublicIPIN.Name) > null
    if ($ProductionRun -eq $true) { Remove-AzureRmPublicIpAddress -Force -Name $PublicIPIN.Name -ResourceGroupName $PublicIPIN.ResourceGroupName }
    else {
      Write-Host " (Test Run) Please be aware that during production run there is" -ForegroundColor Green -NoNewline
      Write-Host " NO " -ForegroundColor Yellow -NoNewline
      Write-Host "delete confirmation" -ForegroundColor Green
    }
  }
}

function DeleteNSG ($NSGIN) {

  if (isNotSkip $NSGIN.Name) {
    Write-Host ("   will delete NSG: " + $NSGIN.Name) -ForegroundColor Red
    Write-Host ("   in resource group: " + $NSGIN.ResourceGroupName) -ForegroundColor Red
    $DeletedNSGs.Add($NSGIN.Name) > null
    if ($ProductionRun -eq $true) { Remove-AzureRmNetworkSecurityGroup -Force -Name $NSGIN.Name -ResourceGroupName $NSGIN.ResourceGroupName }
    else {
      Write-Host " (Test Run) Please be aware that during production run there is" -ForegroundColor Green -NoNewline
      Write-Host " NO " -ForegroundColor Yellow -NoNewline
      Write-Host "delete confirmation" -ForegroundColor Green
    }
  }
}

function DeleteSubnet ($VnetIn,$SubnetIN) {
  if (isNotSkip $SubnetIN) {

    Write-Host ("   will delete Subnet: " + $SubnetIN) -ForegroundColor Red
    Write-Host ("   in Vnet group: " + $VnetIn.Name) -ForegroundColor Red
    $DeletedSubnets.Add("Vnet: " + $VnetIn.Name + " -> " + $SubnetIN) > null
    if ($ProductionRun -eq $true) {
      Remove-AzureRmVirtualNetworkSubnetConfig -Name $SubnetIN -VirtualNetwork $VnetIn
    }
    else {
      Write-Host " (Test Run) Please be aware that during production run there is" -ForegroundColor Green -NoNewline
      Write-Host " NO " -ForegroundColor Yellow -NoNewline
      Write-Host "delete confirmation" -ForegroundColor Green
    }
  }
}

function DeleteVnet {

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'high')]
  param($VnetIn,$ResourceGroupIN)

  if ($YesToAll) {

    Write-Host "------YesToAll---------" -ForegroundColor Yellow
    Write-Host ("deleting Virtual Network: " + $VnetIn) -ForegroundColor Red
    $DeletedVirtualNetworks.Add($VnetIn) > null
    if ($ProductionRun -eq $true) {
      Write-Host "Remove-AzureRmVirtualNetwork -Name $VnetIn -ResourceGroupName $ResourceGroupIN -Verbose"
      Remove-AzureRmVirtualNetwork -Force -Name $VnetIn -ResourceGroupName $ResourceGroupIN -Verbose
    } #WHATIFDOESNOTEXIST
    else { Write-Host " (Test Run) nothing deleted" -ForegroundColor Green }

  } else {
    process {
      if ($PSCmdlet.ShouldProcess($VnetIn)) {
        Write-Host "---------------" -ForegroundColor Yellow
        Write-Host ("deleting Virtual Network: " + $VnetIn) -ForegroundColor Red
        $DeletedVirtualNetworks.Add($VnetIn) > null
        if ($ProductionRun -eq $true) {
          Write-Host "Remove-AzureRmVirtualNetwork -Name $VnetIn -ResourceGroupName $ResourceGroupIN -Verbose"
          Remove-AzureRmVirtualNetwork -Name $VnetIn -ResourceGroupName $ResourceGroupIN -Verbose -Force
        } #WHATIFDOESNOTEXIST
        else { Write-Host " (Test Run) nothing deleted" -ForegroundColor Green }
      }
      else {
        Write-Host (" Deletion NOT confirmed, not deleting Virtual Network: " + $VnetIn) -ForegroundColor Green
      }
    }

  }
}


function NetworkComponents {
  $PublicIPAddresses = Get-AzureRmPublicIpAddress
  #which are not used (not in $VMNICArray)
  #from those, which use external IP addresses
  #GetAll Network Security Groups fill in array - which ones have NetworkInterfaces & Subnets empty -> delete
  #Delete ExternalIPAddresses from unused NIC's
  #Delete Unused NIC's
  #GET ALL UNUSED PIP's
  Write-Host " Public IP Addresses" -ForegroundColor Cyan
  WriteDebug "Public IP addresses"
  foreach ($exIP in $PublicIPAddresses) {
    if ($exIP.Ipconfiguration.id.Count -eq 0) {
      if (isNotSkip $exIP.Name) {
        Write-Host (" " + $exIP.Name + " is not in use") -ForegroundColor Yellow
        WriteDebug (" " + $exIP.Name + " is not in use")
        DeletePublicIPAddress $exIP
      }
    }
    else {
      #FILTER GATEWAYS FROM THIS LIST SO WE CAN ALREADY ADD THEM TO AN ARRAY
      #get the $exIP.Ipconfiguration.id and split it on /.. [4] should be resource group, [7] is virtualNetworkGateways [8] is GW name!
      $IPConfigID = $exIP.Ipconfiguration.id
      WriteDebug " IP is in use"
      WriteDebug $IPConfigID
      $IPConfigIDsplit = $IPConfigID.split("/")
      if (($exIP.Ipconfiguration.id).split("/")[7] -eq 'virtualNetworkGateways') {
        WriteDebug "validating GW IPs later-on"
        #WE FOUND A GATEWAY IP	
        $GatewayArray.Add(($exIP.Ipconfiguration.id).split("/")[8] + "/" + $exIP.Ipconfiguration.id.split("/")[4])
        WriteDebug (" ADDED TO ARRAY: " + ($exIP.Ipconfiguration.id).split("/")[8] + "/" + $exIP.Ipconfiguration.id.split("/")[4])
        Write-Host (" found Public IP address for Azure Gateway in VNet " + ($exIP.Ipconfiguration.id).split("/")[8]) -ForegroundColor Gray
      }
    }
  }
  Write-Host ""
  Write-Host " Network Inferfaces" -ForegroundColor Cyan
  $ALLNics = Get-AzureRmNetworkInterface
  foreach ($Nic in $ALLNics) {
    if ($VMNICArray -notcontains $Nic.id -and !$Nic.VirtualMachine) {
      WriteDebug $Nic.IpConfigurations.id
      #Write-Host $VMNICArray
      if ($NIC.IpConfigurations.PublicIPaddress.id) {
        WriteDebug ("PIP: " + $NIC.IpConfigurations.PublicIPaddress.id)
        $PublicIP = Get-AzureRmPublicIpAddress -Name $NIC.IpConfigurations.PublicIPaddress.id.split("/")[$NIC.IpConfigurations.PublicIPaddress.id.split("/").Count - 1] -ResourceGroupName $NIC.IpConfigurations.PublicIPaddress.id.split("/")[4]
        WriteDebug ("DELETE ATTACHED PIP: " + $PublicIP.Name)
        Write-Host (" " + $PublicIP.Name + " used by orphaned NIC " + $Nic.Name) -ForegroundColor Yellow
        DeletePublicIPAddress $PublicIP
      }
      Write-Host ("  " + $Nic.Name + " may be deleted (not in use)") -ForegroundColor Yellow
      WriteDebug ("  " + $Nic.Name + " may be deleted (not in use)")
      DeleteNIC $Nic
      $NSGCheck.Add($NIC.id) > null
    }
    else {
      Write-Host ("  " + $Nic.Name + " is in use") -ForegroundColor Gray
      WriteDebug ("  " + $Nic.Name + " is in use")
      #FOR ALL THE NIC'S THAT ARE IN USE, ADD THE SUBNET TO AN ARRAY (WILL BE ACTIVE SUBNETS ARRAY)
      $subnetIDArray.Add($Nic.IpConfigurations.subnet.id) > $null
    }
  }
  Write-Host ""
  Write-Host " Network Security Groups" -ForegroundColor Cyan
  WriteDebug " Network Security Groups"
  $AllNSGs = Get-AzureRmNetworkSecurityGroup
  foreach ($NSG in $AllNSGs) {
    if ($NSG.NetworkInterfaces.Count -eq 0 -and $NSG.Subnets.Count -eq 0) {
      Write-Host ("  NSG " + $NSG.Name + " may be deleted (not in use)") -ForegroundColor Yellow
      WriteDebug ("  NSG " + $NSG.Name + " may be deleted (not in use)")
      WriteDebug ("NSGInterfaceCount eq 0")
      WriteDebug ("NSGSubnetCount eq 0")
      DeleteNSG $NSG
    }
    elseif ($NSG.NetworkInterfaces.Count -eq 1 -and $NSGCheck -contains $NSG.NetworkInterfaces.id) {
      Write-Host ("  NSG " + $NSG.Name + " may be deleted (was in use)") -ForegroundColor Yellow
      WriteDebug ("  NSG " + $NSG.Name + " may be deleted (was in use)")
      WriteDebug ("NSGInterfaceCount eq 1")
      WriteDebug ("NSGCheck contains " + $NSG.NetworkInterfaces.id)
      DeleteNSG $NSG
    }
    else {
      Write-Host ("  NSG " + $NSG.Name + " is in use") -ForegroundColor Gray
      WriteDebug (" " + $NSG.Name + " is in use")
    }
  }
}



function AnalyzeVNets {
  Write-Host " Virtual Networks" -ForegroundColor Cyan
  WriteDebug " Virtual Networks"
  $VNETs = Get-AzureRmVirtualNetwork
  Write-Host ("  Found: " + $VNETs.Count + " Virtual Networks") -ForegroundColor Gray
  WriteDebug ("  Found: " + $VNETs.Count + " Virtual Networks")
  #GET ALL GATEWAYS PER RESOURCE GROUP
  Write-Host " Virtual Networks" -ForegroundColor Cyan
  $ResourceGroups = Get-AzureRmResourceGroup
  foreach ($ResGroup in $ResourceGroups) {
    WriteDebug (" Resource Group: " + $ResGroup.ResourceGroupName)
    $NetGateways = Get-AzureRmVirtualNetworkGateway -ResourceGroupName $ResGroup.ResourceGroupName
    foreach ($NetGateway in $NetGateways) {
      WriteDebug (" gateway:" + $NetGateway.Name)
      $subnetID = ($NetGateway.IpConfigurationsText | ConvertFrom-Json).subnet.id
      $subnetIDsplit = $subnetID.split("/")
      $comparesubnetIDtoIP = ($NetGateway.Name + "/" + $subnetIDsplit[4])
      if ($GatewayArray -contains $comparesubnetIDtoIP) {
        Write-Host (" Public IP address assigned to subnet (Azure Gateway) " + $NetGateway.Name) -ForegroundColor Gray
        $GatewaySubnetArray.Add($subnetID) > null
        WriteDebug (" found: " + $comparesubnetIDtoIP + " in GatewayArray")
      }
    }
  }

  foreach ($vnet in $VNETs) {
    if ($vnet.Subnets.id) {
      $SubnetDeleteCounter = 0
      foreach ($subnet in $vnet.Subnets.id) {
        if ($subnetIDArray -notcontains $subnet) {
          if ($GatewaySubnetArray -contains $subnet) {
            Write-Host (" Subnet " + $subnet.split("/")[10] + " being used by Azure Gateway for network " + $subnet.split("/")[8]) -ForegroundColor Green
          }
          else {
            Write-Host (" Subnet " + $subnet.split("/")[10] + " in " + $subnet.split("/")[8] + " is not being used") -ForegroundColor Yellow
            DeleteSubnet $vnet $subnet.split("/")[10]
            $SubnetDeleteCounter++
          }
          #MUST ADD GATEWAY SUBNETS PRIOR TO CALLING NOT BEING USED
        }
      }
    }
    else {
      Write-Host (" Virtual Network " + $vnet.Name + " does not contain any subnets")
      if (isNotSkip $vnet.Name) {
        DeleteVnet $vnet.Name $ResGroup.ResourceGroupName
      }
    }
    if ($SubnetDeleteCounter -eq $vnet.Subnets.id.Count -and $SubnetDeleteCounter -ne 0) {
      if (isNotSkip $vnet.Name) {
        Write-Host (" All subnets in Vnet " + $vnet.Name + " deleted") -ForegroundColor Yellow
        DeleteVnet $vnet.Name $ResGroup.ResourceGroupName
      }
    }
    Write-Host ""
  }
}

if ($Log) {
  $date = (Get-Date).ToString("d-M-y-h.m.s")
  $logname = ("AzureCleanLog-" + $date + ".log")
  #New-Item -Path $pwd.path -Value $LogName -ItemType File
  $LogfileActivated = $pwd.path + "\" + $LogName
  ActivateDebug
} #Activating DEBUG MODE

try {
  Import-Module Azure.Storage
}
catch {
  Write-Host 'Modules NOT LOADED - EXITING'
  exit
}

#LOGIN TO TENANT
#clear
Write-Host ""
Write-Host ""
Write-Host ("-" * 90)
Write-Host ("             Welcome to the Azure unused resources cleanup script") -ForegroundColor Cyan
Write-Host ("-" * 90)
Write-Host "This script comes without any warranty and CAN DELETE resources in your subscriptions" -ForegroundColor Yellow
Write-Host ("-" * 90)
Write-Host "This script will run against your Azure subscriptions can scan for the following resources"
Write-Host " -Storage Accounts"
Write-Host "   +Containers"
Write-Host "   +Files"
Write-Host " -Network"
Write-Host "   +Virtual Networks"
Write-Host "   +Subnets"
Write-Host "   +Public IP addresses"
Write-Host "   +Network Security Groups"
Write-Host
Write-Host "If resources are still in use, they will not be deleted, such as VM files, NIC's etc.."
Write-Host ""
Write-Host "Run the script with -Mode (Full/Storage/Network) for resource type based cleaning"
Write-Host "Run the script with -ProductionRun `$$True to actually delete the resources"
Write-Host ("-" * 90)


if (-not ($Login)) { Add-AzureRmAccount }
$selectedSubscriptions = New-Object System.Collections.ArrayList
$ProcessArray = New-Object System.Collections.ArrayList
$DiskURIArray = New-Object System.Collections.ArrayList
$VMNICArray = New-Object System.Collections.ArrayList
$VMNames = New-Object System.Collections.ArrayList
$VMDiagStorageURL = New-Object System.Collections.ArrayList
$NSGCheck = New-Object System.Collections.ArrayList
$ExternalIPArray = New-Object System.Collections.ArrayList
$filesInContainer = New-Object System.Collections.ArrayList
$subnetArray = New-Object System.Collections.ArrayList
$subnetIDArray = New-Object System.Collections.ArrayList
$GatewayArray = New-Object System.Collections.ArrayList
$GatewaySubnetArray = New-Object System.Collections.ArrayList
$DeletedFiles = New-Object System.Collections.ArrayList
$DeletedContainers = New-Object System.Collections.ArrayList
$DeletedStorageAccounts = New-Object System.Collections.ArrayList
$DeletedPublicIPAddresses = New-Object System.Collections.ArrayList
$DeletedNICs = New-Object System.Collections.ArrayList
$DeletedNSGs = New-Object System.Collections.ArrayList
$DeletedSubnets = New-Object System.Collections.ArrayList
$DeletedVirtualNetworks = New-Object System.Collections.ArrayList
$DeleteStorageAccount = $False

$SkipResource = New-Object System.Collections.ArrayList

Write-Host "The follwing Item will not be deleted. (Edit SkipResouceNameList to add more item) "  -ForegroundColor Yellow
Write-Host "----------"
foreach ($name in $SkipResouceNameList) {
  $SkipResource.Add($name.ToLower()) > $null
    Write-Host $name.ToLower() -ForegroundColor Red
}
Write-Host "----------"

WriteDebug ("Skip to Delete Resources List (Edit $SkipResouceNameList to add more item) :" + $SkipResource)


#GETTING A LIST OF SUBSCRIPTIONS
Write-Host "Getting the subscriptions, please wait..."

$Subscriptions = Get-AzureRmSubscription

foreach ($subscription in $Subscriptions) {
  #ask if it should be included
  $title = $subscription.Name
  $message = "Do you want this subscription to be added to the selection?"
  $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes",`
     "Adds the subscription to the script."
  $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No",`
     "Skips the subscription from scanning."
  $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)
  $result = $host.ui.PromptForChoice($title,$message,$options,0)
  switch ($result) {
    0 {
      $selectedSubscriptions.Add($subscription) > $null
      Write-Host ($subscription.Name + " has been added")
    }
    1 { Write-Host ($subscription.Name + " will be skipped")
    }
  }
}

Write-Host ""
Write-Host "------------------------------------------------------"
Write-Host "Subscriptions selected:" -ForegroundColor Yellow
#Foreach ($entry in $selectedSubscriptions){Write-Host " " + $entry.Subscription.Name -ForegroundColor Yellow}
foreach ($entry in $selectedSubscriptions) { Write-Host " " + $entry.Name -ForegroundColor Yellow }
if ($ProductionRun -eq $true) {
  Write-Host ""
  Write-Host ""
  Write-Host "*************************" -ForegroundColor Yellow
  Write-Host "     !! WARNING !!" -ForegroundColor Red
  Write-Host "!!DATA MAY BE DELETED!!" -ForegroundColor Yellow
  Write-Host "     !! WARNING !!" -ForegroundColor Red
  Write-Host "*************************" -ForegroundColor Yellow
  Write-Host ""
  Write-Host ""
  #Write-Host "Press any key to exit or press p to continue"
  $x = Read-Host 'Press any key to exit or press P to continue'
  if ($x.ToUpper() -ne "P") {
    Write-Host "SAFE QUIT" -ForegroundColor Green
    exit
  }
  Clear-Host
}

foreach ($entry in $selectedSubscriptions) {
  #Write-Host ("scanning: " + $entry.Subscription.Name)
  Write-Host ("scanning: " + $entry.Name)
  #$select=Select-AzureRmSubscription -SubscriptionId $entry.subscriptionID
  $select = Get-AzureRmSubscription -SubscriptionName $entry.Name | Select-AzureRmSubscription
  #$select=$entry

  Write-Host "selected subscription"
  #GET ALL VM PROPERTIES
  Write-Host " collecting VM properties...."
  $VMProperties = GetAllVMProperties
  switch ($Mode.ToLower()) {
    full {
      Write-Host ""
      Write-Host "------------------------------------------------------"
      Write-Host " collecting Storage Accounts ...."
      $StorageAccountStatus = PrepareDeleteStorageAccountContents
      Write-Host ""
      Write-Host "------------------------------------------------------"
      Write-Host " collecting Network components ...."
      $NICStatus = NetworkComponents
      Write-Host ""
      Write-Host "------------------------------------------------------"
      Write-Host " collecting Network components ...."
      $AnalyzeVnetsforme = AnalyzeVNets
      Write-Host "------------------------------------------------------"
      $select = ""
    }

    storage {
      Write-Host ""
      Write-Host "------------------------------------------------------"
      Write-Host " collecting Storage Accounts ...."
      $StorageAccountStatus = PrepareDeleteStorageAccountContents
    }

    network {
      Write-Host ""
      Write-Host "------------------------------------------------------"
      Write-Host " collecting Network components ...."
      $NICStatus = NetworkComponents
      Write-Host ""
      Write-Host "------------------------------------------------------"
      Write-Host " collecting Network components ...."
      $AnalyzeVnetsforme = AnalyzeVNets
      Write-Host "------------------------------------------------------"
      $select = ""
    }
  }
  #if ($ProductionRun -eq $False -or $ProductionRun -eq $null) {
  #Always print the Summary
  if ($True) {
    Write-Host ("==============Summay  for " + $entry.Name);
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Yellow
    if ($ProductionRun -eq $False -or $ProductionRun -eq $null) {
      Write-Host "The following items may be deleted manually (ran test run)" -ForegroundColor Yellow
    } else {
      Write-Host "The following items have been deleted. " -ForegroundColor Yellow
    }
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "Files to be Deleted:"
    foreach ($file in $DeletedFiles) { Write-Host (" " + $file) -ForegroundColor Cyan }
    Write-Host ""
    Write-Host "Containers to be Deleted:"
    foreach ($container in $DeletedContainers) { Write-Host (" " + $container) -ForegroundColor Cyan }
    Write-Host ""

    Write-Host "Storage Accounts to be Deleted:"
    foreach ($SA in $DeletedStorageAccounts) { Write-Host (" " + $SA) -ForegroundColor Cyan }
    Write-Host ""

    Write-Host "Public IP Addresses to be Deleted:"
    foreach ($PIP in $DeletedPublicIPAddresses) { Write-Host (" " + $PIP) -ForegroundColor Cyan }
    Write-Host ""

    Write-Host "NIC's to be Deleted:"
    foreach ($NIC in $DeletedNICs) { Write-Host (" " + $NIC) -ForegroundColor Cyan }
    Write-Host ""

    Write-Host "NSG's to be Deleted:"
    foreach ($NS in $DeletedNSGs) { Write-Host (" " + $NS) -ForegroundColor Cyan }
    Write-Host ""

    Write-Host "Subnets to be Deleted (Due to some API issue, this item may not be removed successfully in some situations, You can go to Azure Portal to double check):" -ForegroundColor Red
    foreach ($sub in $DeletedSubnets) { Write-Host (" " + $sub) -ForegroundColor Cyan }
    Write-Host ""

    Write-Host "Virtual Networks to be Deleted (Due to some API issue, this item may not be removed successfully in some situations, You can go to Azure Portal to double check):" -ForegroundColor Red
    foreach ($vinet in $DeletedVirtualNetworks) { Write-Host (" " + $vinet) -ForegroundColor Cyan }
    Write-Host ""


    Write-Host "-----------------------------------------------------------------" -ForegroundColor Yellow
    if ($ProductionRun -eq $False -or $ProductionRun -eq $null) {
      Write-Host "Items above will be deleted in production run (-production `$$true)" -ForegroundColor Yellow
    } else {
      Write-Host "The following items had been deleted.( you can ran again to check whether the items have been deleted.)" -ForegroundColor Yellow
    }

    Write-Host "-----------------------------------------------------------------" -ForegroundColor Yellow
  }
}
Write-Host "!!!!Edit SkipResouceNameList to add Skip Resouce if you want!! " -ForegroundColor Cyan 
Write-Host ""

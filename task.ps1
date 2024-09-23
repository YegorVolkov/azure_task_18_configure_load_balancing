$location =                             "uksouth"
$resourceGroupName =                    "mate-azure-task-18"

# Network Settings
$virtualNetworkName =                   "todoapp"
$vnetAddressPrefix =                    "10.20.30.0/24"

$webSubnetName =                        "webservers"
$webSubnetIpRange =                     "10.20.30.0/26"

$mngSubnetName =                        "management"
$mngSubnetIpRange =                     "10.20.30.128/26"

# SSH settings
$sshKeyName =                           "linuxboxsshkey"
$sshKeyPublicKey =                      Get-Content "~/.ssh/id_rsa.pub"

# Domain settings
$privateDnsZoneName =                   "or.nottodo"
$webSetSubdomain =                      "todo"

# Boot Diagnostic Storage Account settings
$bootStorageAccName =                   "bootdiagnosstorageacc"
$bootStSkuName =                        "Standard_LRS"
$bootStKind =                           "StorageV2"
$bootStAccessTier =                     "Hot"
$bootStMinimumTlsVersion =              "TLS1_0"

# VM settings
$vmSize =                               "Standard_B1s"
$webVmName =                            "webserver"
$jumpboxVmName =                        "jumpbox"
$dnsLabel =                             "matetask" + (Get-Random -Count 1)

# OS settings:
$osUser =                               "yegor"
$osUserPassword =                       "P@ssw0rd1234"
  $SecuredPassword = ConvertTo-SecureString `
    $osUserPassword -AsPlainText -Force
  $cred = New-Object System.Management.Automation.PSCredential `
    ($osUser, $SecuredPassword)
$osPublisherName =                      "Canonical"
$osOffer =                              "0001-com-ubuntu-server-jammy"
$osSku =                                "22_04-lts-gen2"
$osVersion =                            "latest"
$osDiskSizeGB =                         64
$osDiskType =                           "Premium_LRS"

$lbName = "loadbalancer"
$lbIpAddress = "10.20.30.62"


Write-Host "Creating a resource group $resourceGroupName ..."
New-AzResourceGroup `
  -Name                                 $resourceGroupName `
  -Location                             $location

Write-Host "Creating web network security group..."
$webHttpRule = New-AzNetworkSecurityRuleConfig `
  -Name                                 "web" `
  -Description                          "Allow HTTP" `
  -Access                               "Allow" `
  -Protocol                             "Tcp" `
  -Direction                            "Inbound" `
  -Priority                             100 `
  -SourceAddressPrefix                  "Internet" `
  -SourcePortRange                      * `
  -DestinationAddressPrefix             * `
  -DestinationPortRange                 80,443
$webNsg = New-AzNetworkSecurityGroup `
  -ResourceGroupName                    $resourceGroupName `
  -Location                             $location `
  -Name                                 $webSubnetName `
  -SecurityRules                        $webHttpRule

Write-Host "Creating mngSubnet network security group..."
$mngSshRule = New-AzNetworkSecurityRuleConfig `
  -Name                                 "ssh" `
  -Description                          "Allow SSH" `
  -Access                               "Allow" `
  -Protocol                             "Tcp" `
  -Direction                            "Inbound" `
  -Priority                             100 `
  -SourceAddressPrefix                  "Internet" `
  -SourcePortRange                      * `
  -DestinationAddressPrefix             * `
  -DestinationPortRange                 22
$mngNsg = New-AzNetworkSecurityGroup `
  -ResourceGroupName                    $resourceGroupName `
  -Location                             $location `
  -Name                                 $mngSubnetName `
  -SecurityRules                        $mngSshRule

Write-Host "Creating a virtual network ..."
$webSubnet = New-AzVirtualNetworkSubnetConfig `
  -Name                                 $webSubnetName `
  -AddressPrefix                        $webSubnetIpRange `
  -NetworkSecurityGroup                 $webNsg
$mngSubnet = New-AzVirtualNetworkSubnetConfig `
  -Name                                 $mngSubnetName `
  -AddressPrefix                        $mngSubnetIpRange `
  -NetworkSecurityGroup                 $mngNsg
$vnetObj = New-AzVirtualNetwork `
  -Name                                 $virtualNetworkName `
  -ResourceGroupName                    $resourceGroupName `
  -Location                             $location `
  -AddressPrefix                        $vnetAddressPrefix `
  -Subnet                               $webSubnet,`
                                        $mngSubnet
  $webSubnetId = (
    $vnetObj.Subnets |
    Where-Object { $_.Name -eq $webSubnetName }
    ).Id
  $mngSubnetId = (
    $vnetObj.Subnets |
    Where-Object { $_.Name -eq $mngSubnetName }
    ).Id

Write-Host "Creating Storage Account for boot diagnostic ..."
New-AzStorageAccount `
  -ResourceGroupName                    $resourceGroupName `
  -Name                                 $bootStorageAccName `
  -Location                             $location `
  -SkuName                              $bootStSkuName `
  -Kind                                 $bootStKind `
  -AccessTier                           $bootStAccessTier `
  -MinimumTlsVersion                    $bootStMinimumTlsVersion


for (($zone = 1); ($zone -le 2); ($zone++) ) {
  Write-Host "Creating a NIC for web server VM #${zone}..."
  $vmName = "$webVmName-$zone"
  $ipConfig = New-AzNetworkInterfaceIpConfig `
    -Name                                 "${vmName}-ipconfig" `
    -SubnetId                             $webSubnetId
  $nicObj = New-AzNetworkInterface -Force `
    -Name                                 "${vmName}-NIC" `
    -ResourceGroupName                    $resourceGroupName `
    -Location                             $location `
    -IpConfiguration                      $ipConfig
  Write-Host "Creating a web server VM #${zone}..."
  $vmconfig = New-AzVMConfig `
    -VMName                               $vmName `
    -VMSize                               $vmSize
  $vmconfig = Set-AzVMSourceImage `
    -VM                                   $vmconfig `
    -PublisherName                        $osPublisherName `
    -Offer                                $osOffer `
    -Skus                                 $osSku `
    -Version                              $osVersion
  $vmconfig = Set-AzVMOSDisk `
    -VM                                   $vmconfig `
    -Name                                 "${vmName}-OSDisk" `
    -CreateOption                         "FromImage" `
    -DeleteOption                         "Delete" `
    -DiskSizeInGB                         $osDiskSizeGB `
    -Caching                              "ReadWrite" `
    -StorageAccountType                   $osDiskType
  $vmconfig = Set-AzVMOperatingSystem `
    -VM                                   $vmconfig `
    -ComputerName                         $vmName `
    -Linux                                `
    -Credential                           $cred
  $vmconfig = Add-AzVMNetworkInterface `
    -VM                                   $vmconfig `
    -Id                                   $nicObj.Id
  $vmconfig = Set-AzVMBootDiagnostic `
    -VM                                   $vmconfig `
    -Enable                               `
    -ResourceGroupName                    $resourceGroupName `
    -StorageAccountName                   $bootStorageAccName
  New-AzVM `
    -ResourceGroupName                    $resourceGroupName `
    -Location                             $location `
    -VM                                   $vmconfig
  $scriptUrl = "https://raw.githubusercontent.com/YegorVolkov/azure_task_18_configure_load_balancing/dev/install-app.sh"
  Set-AzVMExtension `
    -ResourceGroupName                    $resourceGroupName `
    -VMName                               $vmName `
    -Name                                 'CustomScript' `
    -Publisher                            'Microsoft.Azure.Extensions' `
    -ExtensionType                        'CustomScript' `
    -TypeHandlerVersion                   '2.1' `
    -Settings @{
        "fileUris" =                      @($scriptUrl)
        "commandToExecute" =              './install-app.sh'
    }
}

Write-Host "Creating an SSH key resource ..."
New-AzSshKey `
  -Name                                 $sshKeyName `
  -ResourceGroupName                    $resourceGroupName `
  -PublicKey                            $sshKeyPublicKey
Write-Host "Creating a public IP ..."
$jumpboxVmPubipObj = New-AzPublicIpAddress `
  -Name                                 "${jumpboxVmName}-pubip" `
  -ResourceGroupName                    $resourceGroupName `
  -Location                             $location `
  -Sku                                  "Basic" `
  -AllocationMethod                     "Dynamic" `
  -DomainNameLabel                      $dnsLabel
Write-Host "Creating a NIC for management VM ..."
$ipConfig = New-AzNetworkInterfaceIpConfig `
  -Name                                 "${jumpboxVmName}-ipconfig" `
  -SubnetId                             $mngSubnetId `
  -PublicIpAddressId                    $jumpboxVmPubipObj.Id
$nicObj = New-AzNetworkInterface -Force `
  -Name                                 "${jumpboxVmName}-NIC" `
  -ResourceGroupName                    $resourceGroupName `
  -Location                             $location `
  -IpConfiguration                      $ipConfig
Write-Host "Creating a management VM ..."
$vmconfig = New-AzVMConfig `
  -VMName                               $jumpboxVmName `
  -VMSize                               $vmSize
$vmconfig = Set-AzVMSourceImage `
  -VM                                   $vmconfig `
  -PublisherName                        $osPublisherName `
  -Offer                                $osOffer `
  -Skus                                 $osSku `
  -Version                              $osVersion
$vmconfig = Set-AzVMOSDisk `
  -VM                                   $vmconfig `
  -Name                                 "${jumpboxVmName}-OSDisk" `
  -CreateOption                         FromImage `
  -DeleteOption                         Delete `
  -DiskSizeInGB                         $osDiskSizeGB `
  -Caching                              ReadWrite `
  -StorageAccountType                   $osDiskType
$vmconfig = Set-AzVMOperatingSystem `
  -VM                                   $vmconfig `
  -ComputerName                         $jumpboxVmName `
  -Linux                                `
  -Credential                           $cred `
  -DisablePasswordAuthentication
$vmconfig = Add-AzVMNetworkInterface `
  -VM                                   $vmconfig `
  -Id                                   $nicObj.Id
$vmconfig = Set-AzVMBootDiagnostic `
  -VM                                   $vmconfig `
  -Enable                               `
  -ResourceGroupName                    $resourceGroupName `
  -StorageAccountName                   $bootStorageAccName
New-AzVM `
  -ResourceGroupName                    $resourceGroupName `
  -Location                             $location `
  -VM                                   $vmconfig `
  -SshKeyName                           $sshKeyName

Write-Host "Creating a Private Dns Zone ..."
New-AzPrivateDnsZone `
  -Name                                 $privateDnsZoneName `
  -ResourceGroupName                    $resourceGroupName

Write-Host "Auto-Assigning the DNS to VMs via 'Private Dns Virtual Network Link' ..."
New-AzPrivateDnsVirtualNetworkLink `
  -Name                                 "dnslink.${privateDnsZoneName}" `
  -ResourceGroupName                    $resourceGroupName `
  -ZoneName                             $privateDnsZoneName `
  -VirtualNetworkId                     $vnetObj.Id `
  -EnableRegistration

Write-Host "Creating an 'A' DNS record (Assigning the ipv4 to management VM) ..."
New-AzPrivateDnsRecordSet `
  -Name                                 $webSetSubdomain `
  -RecordType                           A `
  -ResourceGroupName                    $resourceGroupName `
  -TTL                                  1800 `
  -ZoneName                             $privateDnsZoneName `
  -PrivateDnsRecords                    @(
    New-AzPrivateDnsRecordConfig `
      -IPv4Address                      $lbIpAddress
    )

# Write your code here ->
Write-Host "Creating a load balancer ..."


# Write-Host "Adding VMs to the backend pool"
# $vms = Get-AzVm -ResourceGroupName $resourceGroupName | Where-Object {$_.Name.StartsWith($webVmName)}
# foreach ($vm in $vms) {
#    $nic = Get-AzNetworkInterface -ResourceGroupName $resourceGroupName | Where-Object {$_.Id -eq $vm.NetworkProfile.NetworkInterfaces.Id}
#    $ipCfg = $nic.IpConfigurations | Where-Object {$_.Primary}
#    $ipCfg.LoadBalancerBackendAddressPools.Add($bepool)
#    Set-AzNetworkInterface -NetworkInterface $nic
# }

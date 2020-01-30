#PowerShell.exe -ExecutionPolicy Bypass -File \\fs11\Install\SqlInstall\_SCRIPTS\installSqlFailoverCluster.ps1
# set-executionpolicy Bypass -scope currentuser
# $cred = Get-Credential
# $passwordUser4Sql = Read-Host -assecurestring "Please enter password for User4Sql"
# $passwordUser4SqlAgent = Read-Host -assecurestring "Please enter password for User4SqlAgent"
# \\fs11\Install\SqlInstall\_SCRIPTS\installSqlFailoverCluster.ps1 $cred "VDB11A" "VDB11B" "CVDB11" "SQL11C" "SQL2016C" "\\fs12\SqlRootA" "n" $passwordUser4Sql $passwordUser4SqlAgent "1"

param($Credential, $firstServer, $secondServer, $clusterName, $failoverRoleName, $instanceName, $sqlRootPath, $createCluster, $passwordUser4Sql, $passwordUser4SqlAgent, $startFromStep, $setupPath = ".\sql2016sp2\Setup.exe")


if($ENV:START_STEP -ne $NULL)		{	$startFromStep = $ENV:START_STEP} elseif ($startFromStep -ne $NULL) {} else {$startFromStep = Read-Host "Start from step `n1. Check credentials `n2. Create failover cluster `n3. SQL instance - create configuration files `n4. SQL instance - TempDB dir `n5. SQL instance - Sql Root dir `n6. SQL instance - WSManCredSSP `n7. SQL instance - install on first server `n8. SQL instance - install on second server`n9. SQL instance - SPN`n10. SQL instance - tcpip `n11. SQL instance - copy files for Max Server Memory`nSelect"}


#$configurationPath = "\\vfs100\Install\SqlInstall"
$configurationPath = (get-item $PSScriptRoot).parent.fullname 
#$scriptsPath = "$configurationPath\_SCRIPTS"
$scriptsPath = $PSScriptRoot

. "$PSScriptRoot\f_EnableTCPIP.ps1"
. "$PSScriptRoot\f_CreateTempDBFolder.ps1"
. "$PSScriptRoot\f_InstallSqlInstance.ps1"
. "$PSScriptRoot\f_Test-Credential.ps1"

Set-Item WSMan:\localhost\Shell\MaxMemoryPerShellMB 2048

if($ENV:SECURE_PASSWORD -ne $NULL)	{	$SrvPassword = ConvertTo-SecureString $($ENV:SECURE_PASSWORD) -AsPlainText -Force}
if($ENV:SECURE_USER -ne $NULL)		{	$Credential = New-Object System.Management.Automation.PSCredential ($ENV:SECURE_USER, $SrvPassword)}
if($ENV:FIRST_SERVER -ne $NULL)		{	$firstServer = $ENV:FIRST_SERVER}
if($ENV:SECOND_SERVER -ne $NULL)	{	$secondServer = $ENV:SECOND_SERVER}
if($ENV:CLUSTER_NAME -ne $NULL)		{	$clusterName = $ENV:CLUSTER_NAME}
if($ENV:FAILOVERROLE_NAME -ne $NULL){	$failoverRoleName = $ENV:FAILOVERROLE_NAME}
if($ENV:INSTANCE_NAME -ne $NULL)	{	$instanceName = $ENV:INSTANCE_NAME}
if($ENV:SQLROOT_PATH -ne $NULL)		{	$sqlRootPath = $ENV:SQLROOT_PATH}
if($ENV:CREATECLUSTER -ne $NULL)	{	$createCluster = $ENV:CREATECLUSTER; $unattended = $TRUE}
if($createCluster -ne $NULL)		{	$unattended = $TRUE}

if($ENV:PASSWORD_USER4SQL -ne $NULL)		{	$passwordUser4Sql = $ENV:PASSWORD_USER4SQL}
if($ENV:PASSWORD_USER4SQLAGENT -ne $NULL)	{	$passwordUser4SqlAgent = $ENV:PASSWORD_USER4SQLAGENT}


if($Credential -eq $NULL)			{	$Credential = Get-Credential -Message "Any admin account with proper permissions"}
if($firstServer -eq $NULL)			{	$firstServer = Read-Host "Enter first server name for failover clustering (e.g. VDB01A)"}
if($secondServer -eq $NULL)			{	$secondServer = Read-Host "Enter second server name for failover clustering (e.g. VDB01B)"}

$clusterNodes = @($firstServer, $secondServer)

if($instanceName -eq $NULL)			{	$instanceName = Read-Host "Enter SQL named instance name (e.g. SQL2016A)"}
if($failoverRoleName -eq $NULL)		{	$failoverRoleName = Read-Host "Enter SQL role name (e.g. SQL01A)"}
if($sqlRootPath -eq $NULL)			{	$sqlRootPath = Read-Host "Enter SQL root path (e.g. \\fs01\SqlRoot)"}
if($passwordUser4Sql -eq $NULL)		{	$passwordUser4Sql = Read-Host -assecurestring "Please enter password for User4Sql"}
if($passwordUser4SqlAgent -eq $NULL){	$passwordUser4SqlAgent = Read-Host -assecurestring "Please enter password for User4SqlAgent"}

$domainName = (Get-WmiObject Win32_ComputerSystem).domain

if(1 -ge $startFromStep)
{
	####################################
	# Step 1
	# Check credentials
	Write-Host "$(Get-Date):: #################################### Check credentials"
	####################################

	### Check credentials
	if(!(Test-Credential -Credential (New-Object System.Management.Automation.PSCredential ("User4Sql", $passwordUser4Sql)))) {Write-Host "$(Get-Date):: Wrong credentials for USer4Sql"; break}
	if(!(Test-Credential -Credential (New-Object System.Management.Automation.PSCredential ("User4SqlAgent", $passwordUser4SqlAgent)))) {Write-Host "$(Get-Date):: Wrong credentials for USer4SqlAgent"; break}
}



if(2 -ge $startFromStep)
{
	####################################
	# Step 2
	# Create failover cluster
	Write-Host "$(Get-Date):: #################################### Create failover cluster"
	####################################
	while("y","n" -notcontains $createCluster )
	{
		if($createCluster -eq $NULL)	{	$createCluster = Read-Host "Create new failover cluster? (y/n)"}
	}
	if($createCluster -eq "y")
	{
		if($clusterName -eq $NULL)		{	$clusterName = Read-Host "Enter failover clusster name name (e.g. CVDB01)"}
		if(!$unattended) 				{	Read-Host "$(Get-Date):: Create cluster on nodes $firstServer and $secondServer with cluster name $clusterName. Press Enter to start"}
		
		Write-Host "$(Get-Date):: Configure CD drive letter on $firstServer, $secondServer"
		Invoke-Command -ComputerName $clusterNodes -FilePath $scriptsPath\configure_CDROM-DriveD.ps1 -Credential $Credential
		Write-Host "$(Get-Date):: Disable NETBIOS on $firstServer, $secondServer"
		Invoke-Command -ComputerName $clusterNodes -FilePath $scriptsPath\configure_NetworkNetbios.ps1 -Credential $Credential

		
		Write-Host "$(Get-Date):: Installing Failover-Clustering"
		Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools -ComputerName $firstServer
		Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools -ComputerName $secondServer
		
		Write-Host "$(Get-Date):: Restart $firstServer, $secondServer"
		Restart-Computer $clusterNodes -Protocol WSMan -Wait -For PowerShell -Force
		
		Start-Sleep 20 #Failsafe as Hyper-V needs 2 reboots and sometimes it happens, that during the first reboot the restart-computer evaluates the machine is up
		Test-Cluster -Node $clusterNodes -Include Inventory,Network,"System Configuration"
		
		Write-Host "$(Get-Date):: Forming cluster $clusterName from nodes $firstServer,$secondServer"
		New-Cluster -Name $clusterName -Node $clusterNodes -NoStorage
		
		Start-Sleep 5
		Clear-DnsClientCache
	}
	else
	{
		$clusterName = $(Get-Cluster -Name $firstServer -ErrorAction Stop).Name
	}
}

if(3 -ge $startFromStep)
{
	####################################
	# Step 3
	# SQL instance - create configuration files
	Write-Host "$(Get-Date):: #################################### SQL instance - create configuration files for $instanceName"
	####################################
	$clusterName = $(Get-Cluster -Name $firstServer -ErrorAction Stop).Name
	$sqlConfPrimary = gc $configurationPath\BASE_Primary_ConfigurationFile.ini
	$sqlConfSecondary = gc $configurationPath\BASE_Secondary_ConfigurationFile.ini
	$clusterNetworkName = $(Get-ClusterNetwork -Cluster $clusterName | Select Name)[0].Name


	$sqlConfPrimary = $sqlConfPrimary | foreach-object {$_ -replace "BASE_INSTANCENAME", $instanceName}	
	$sqlConfPrimary = $sqlConfPrimary | foreach-object {$_ -replace "BASE_CLUSTERNETWORK", $clusterNetworkName}	
	$sqlConfPrimary = $sqlConfPrimary | foreach-object {$_ -replace "BASE_FAILOVERROLENAME", $failoverRoleName}	
	$sqlConfPrimary = $sqlConfPrimary | foreach-object {$_ -replace "BASE_DOMAINNAME", $domainName}	
	$sqlConfPrimary = $sqlConfPrimary | foreach-object {$_ -replace "BASE_ROOTPATH", $sqlRootPath}
	if($instanceName.Substring($instanceName.Length-1) -eq "A")
	{
		$sqlConfPrimary = $sqlConfPrimary | foreach-object {$_ -replace "BASE_TEMPDIR", "D:\SqlTempA"}
	}
	elseif($instanceName.Substring($instanceName.Length-1) -eq "B")
	{
		$sqlConfPrimary = $sqlConfPrimary | foreach-object {$_ -replace "BASE_TEMPDIR", "D:\SqlTempB"}
	}
	elseif($instanceName.Substring($instanceName.Length-1) -eq "C")
	{
		$sqlConfPrimary = $sqlConfPrimary | foreach-object {$_ -replace "BASE_TEMPDIR", "D:\SqlTempC"}
	}
	elseif($instanceName.Substring($instanceName.Length-1) -eq "D")
	{
		$sqlConfPrimary = $sqlConfPrimary | foreach-object {$_ -replace "BASE_TEMPDIR", "D:\SqlTempD"}
	}
	else
	{
		Write-Host "$(Get-Date):: Skipping SQL instance - create configuration files. Instance name do not match naming requirements"
		Break
	}
	$sqlConfPrimary | Out-file "${configurationPath}\${domainName}_${failoverRoleName}_${instanceName}_Primary_ConfigurationFile.ini" -Force

	$sqlConfSecondary = $sqlConfSecondary | foreach-object {$_ -replace "BASE_INSTANCENAME", $instanceName}	
	$sqlConfSecondary = $sqlConfSecondary | foreach-object {$_ -replace "BASE_CLUSTERNETWORK", $clusterNetworkName}	
	$sqlConfSecondary = $sqlConfSecondary | foreach-object {$_ -replace "BASE_FAILOVERROLENAME", $failoverRoleName}	
	$sqlConfSecondary = $sqlConfSecondary | foreach-object {$_ -replace "BASE_DOMAINNAME", $domainName}	
	$sqlConfSecondary = $sqlConfSecondary | foreach-object {$_ -replace "BASE_ROOTPATH", $sqlRootPath}	
	$sqlConfSecondary | Out-file "${configurationPath}\${domainName}_${failoverRoleName}_${instanceName}_Secondary_ConfigurationFile.ini" -Force
}

if(4 -ge $startFromStep)
{
	####################################
	# Step 4
	# SQL instance - TempDB dir
	Write-Host "$(Get-Date):: #################################### SQL instance - TempDB dir for $instanceName"
	####################################
	if($instanceName.Substring($instanceName.Length-1) -eq "A")
	{
		Write-Host "$(Get-Date):: Creating TempDB directory D:\SqlTempA for $instanceName"
		CreateTempDBFolder -Credential $Credential -ServerName $firstServer -tempDbPath "D:\SqlTempA"
		CreateTempDBFolder -Credential $Credential -ServerName $secondServer -tempDbPath "D:\SqlTempA"
	}
	elseif($instanceName.Substring($instanceName.Length-1) -eq "B")
	{
		Write-Host "$(Get-Date):: Creating TempDB directory D:\SqlTempB for $instanceName"
		CreateTempDBFolder -Credential $Credential -ServerName $firstServer -tempDbPath "D:\SqlTempB"
		CreateTempDBFolder -Credential $Credential -ServerName $secondServer -tempDbPath "D:\SqlTempB"
	}
	elseif($instanceName.Substring($instanceName.Length-1) -eq "C")
	{
		Write-Host "$(Get-Date):: Creating TempDB directory D:\SqlTempC for $instanceName"
		CreateTempDBFolder -Credential $Credential -ServerName $firstServer -tempDbPath "D:\SqlTempC"
		CreateTempDBFolder -Credential $Credential -ServerName $secondServer -tempDbPath "D:\SqlTempC"
	}
	elseif($instanceName.Substring($instanceName.Length-1) -eq "D")
	{
		Write-Host "$(Get-Date):: Creating TempDB directory D:\SqlTempD for $instanceName"
		CreateTempDBFolder -Credential $Credential -ServerName $firstServer -tempDbPath "D:\SqlTempD"
		CreateTempDBFolder -Credential $Credential -ServerName $secondServer -tempDbPath "D:\SqlTempD"
	}
	else
	{
		Write-Host "$(Get-Date):: Skipping TempDB directory creation. Instance name do not match naming requirements"
		Break
	}
}

if(5 -ge $startFromStep)
{
	####################################
	# Step 5
	# SQL instance - Sql Root dir
	Write-Host "$(Get-Date):: #################################### SQL instance - Sql Root dir"
	####################################
	Write-Host "$(Get-Date):: Creating SQL Root directory $sqlRootPath\$failoverRoleName"
	if(!(Test-Path "$sqlRootPath\$failoverRoleName"))
	{
		Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false  | Out-Null
		Install-Module -Name NTFSSecurity -Force -Confirm:$false | Out-Null

		New-Item -ItemType directory -Path "$sqlRootPath\$failoverRoleName" | Out-Null
		Add-NTFSAccess -Path "$sqlRootPath\$failoverRoleName" -Account 'User4Sql', 'User4SqlAgent' -AccessRights FullControl
	}
}


if(6 -ge $startFromStep)
{
	####################################
	# Step 6
	# SQL instance - WSManCredSSP 
	Write-Host "$(Get-Date):: #################################### SQL instance - WSManCredSSP"
	####################################
	Enable-WSManCredSSP –Role client –DelegateComputer * -Force | Out-Null #########
	Write-Output ("$(Get-Date):: Double-hop (client) for * configured.") #########

		
	$configFileP = "${domainName}_${failoverRoleName}_${instanceName}_Primary_ConfigurationFile.ini"
	$configFileS = "${domainName}_${failoverRoleName}_${instanceName}_Secondary_ConfigurationFile.ini"

	Invoke-Command -ComputerName $firstServer,$secondServer  -scriptblock{ #########
				Enable-WSManCredSSP –Role Server -Force | Out-Null #########
				Write-Output ("$(Get-Date):: Double-hop (server) on {0} configured." -f $($env:computername)) #########
	} -Credential $Credential #########
}

if(7 -ge $startFromStep)
{
	####################################
	# Step 7
	# SQL instance - install on first server
	Write-Host "$(Get-Date):: SQL instance - install on first server"
	####################################

	###Read-Host "Ready to install? [press any key]"

	InstallSqlInstance -Credential $Credential -ServerName $firstServer -passwordUser4Sql $passwordUser4Sql -passwordUser4SqlAgent $passwordUser4SqlAgent -configFile $configFileP -configurationPath $configurationPath -setupPath $setupPath
}

if(8 -ge $startFromStep)
{
	####################################
	# Step 8
	# SQL instance - install on second server
	Write-Host "$(Get-Date):: SQL instance - install on second server"
	####################################
	#Read-Host "Ready to install on second server? [press any key]"
	InstallSqlInstance -Credential $Credential -ServerName $secondServer -passwordUser4Sql $passwordUser4Sql -passwordUser4SqlAgent $passwordUser4SqlAgent -configFile $configFileS -configurationPath $configurationPath -setupPath $setupPath
}

if(9 -ge $startFromStep)
{
	####################################
	# Step 9
	# SQL instance - SPN
	Write-Host "$(Get-Date):: #################################### SQL instance - SPN"
	####################################
	if($instanceName.Substring($instanceName.Length-1) -eq "A")
	{
		Write-Host "$(Get-Date):: Set SPN for $failoverRoleName cluster: 1432, $instanceName"
		&{ setspn -S MSSQLSvc/${failoverRoleName}.${domainName}:${instanceName} ${domainName}\User4Sql }
		&{ setspn -S MSSQLSvc/${failoverRoleName}.${domainName}:1432 ${domainName}\User4Sql }
		&{ setspn -S MSSQLSvc/${failoverRoleName}.${domainName} ${domainName}\User4Sql }
	}
	elseif($instanceName.Substring($instanceName.Length-1) -eq "B")
	{
		Write-Host "$(Get-Date):: Set SPN for $failoverRoleName cluster: 1431, $instanceName"
		&{ setspn -S MSSQLSvc/${failoverRoleName}.${domainName}:${instanceName} ${domainName}\User4Sql }
		&{ setspn -S MSSQLSvc/${failoverRoleName}.${domainName}:1431 ${domainName}\User4Sql }
		&{ setspn -S MSSQLSvc/${failoverRoleName}.${domainName} ${domainName}\User4Sql }
	}
	elseif($instanceName.Substring($instanceName.Length-1) -eq "C")
	{
		Write-Host "$(Get-Date):: Set SPN for $failoverRoleName cluster: 1432, $instanceName"
		&{ setspn -S MSSQLSvc/${failoverRoleName}.${domainName}:${instanceName} ${domainName}\User4Sql }
		&{ setspn -S MSSQLSvc/${failoverRoleName}.${domainName}:1430 ${domainName}\User4Sql }
		&{ setspn -S MSSQLSvc/${failoverRoleName}.${domainName} ${domainName}\User4Sql }
	}
	elseif($instanceName.Substring($instanceName.Length-1) -eq "D")
	{
		Write-Host "$(Get-Date):: Set SPN for $failoverRoleName cluster: 1431, $instanceName"
		&{ setspn -S MSSQLSvc/${failoverRoleName}.${domainName}:${instanceName} ${domainName}\User4Sql }
		&{ setspn -S MSSQLSvc/${failoverRoleName}.${domainName}:1429 ${domainName}\User4Sql }
		&{ setspn -S MSSQLSvc/${failoverRoleName}.${domainName} ${domainName}\User4Sql }
	}
	else
	{
		Write-Host "$(Get-Date):: Skipping SPN configuration. Instance name do not match naming requirements"
		Break
	}
}


if(10 -ge $startFromStep)
{
	####################################
	# Step 10
	# SQL instance - tcpip
	Write-Host "$(Get-Date):: #################################### SQL instance - tcpip"
	####################################
	if($instanceName.Substring($instanceName.Length-1) -eq "A")
	{
		Write-Host "$(Get-Date):: Enabling TCP 1432 for $firstServer $instanceName"
		enableTcpip -Port "1432" -Credential $Credential -ServerName $firstServer -InstanceName $instanceName
		Write-Host "$(Get-Date):: Enabling TCP 1432 for $secondServer $instanceName"
		enableTcpip -Port "1432" -Credential $Credential -ServerName $secondServer -InstanceName $instanceName
	}
	elseif($instanceName.Substring($instanceName.Length-1) -eq "B")
	{
		Write-Host "$(Get-Date):: Enabling TCP 1431 for $firstServer $instanceName"
		enableTcpip -Port "1431" -Credential $Credential -ServerName $firstServer -InstanceName $instanceName
		Write-Host "$(Get-Date):: Enabling TCP 1431 for $secondServer $instanceName"
		enableTcpip -Port "1431" -Credential $Credential -ServerName $secondServer -InstanceName $instanceName
	}
	elseif($instanceName.Substring($instanceName.Length-1) -eq "C")
	{
		Write-Host "$(Get-Date):: Enabling TCP 1430 for $firstServer $instanceName"
		enableTcpip -Port "1430" -Credential $Credential -ServerName $firstServer -InstanceName $instanceName
		Write-Host "$(Get-Date):: Enabling TCP 1430 for $secondServer $instanceName"
		enableTcpip -Port "1430" -Credential $Credential -ServerName $secondServer -InstanceName $instanceName
	}
	elseif($instanceName.Substring($instanceName.Length-1) -eq "D")
	{
		Write-Host "$(Get-Date):: Enabling TCP 1429 for $firstServer $instanceName"
		enableTcpip -Port "1429" -Credential $Credential -ServerName $firstServer -InstanceName $instanceName
		Write-Host "$(Get-Date):: Enabling TCP 1429 for $secondServer $instanceName"
		enableTcpip -Port "1429" -Credential $Credential -ServerName $secondServer -InstanceName $instanceName
	}
	else
	{
		Write-Host "$(Get-Date):: Skipping TCP configuration. Instance name do not match naming requirements"
		Break
	}
}


if(11 -ge $startFromStep)
{
	####################################
	# Step 12
	# SQL instance - copy files for Max Server Memory
	Write-Host "$(Get-Date):: #################################### SQL instance - copy files for Max Server Memory"
	####################################

	
	Invoke-Command -ComputerName $clusterNodes -scriptblock{ 
		param(		
		[System.Management.Automation.PSCredential]$Credential,
		[string]$configurationPath,
		[string]$domainName,
		[string]$failoverRoleName
		)
		Write-Output ("$(Get-Date):: [{0}] Copy files - Max Server Memory." -f $($env:computername)) 
		
		New-PSDrive -Name U -PSProvider filesystem -Root ${configurationPath} -Credential $Credential | Out-Null
		Push-Location
		Set-Location 'U:\'
		
		if(!(Test-Path "D:\Vulcan\Tasks\SqlMaxServerMemory")) {New-Item -ItemType directory -Path "D:\Vulcan\Tasks\SqlMaxServerMemory"}
		
		Write-Host "$(Get-Date):: ${domainName}_${failoverRoleName}_MaxServerMemory_Application.config"
		Copy-Item "U:\Vulcan_Tasks_SqlMaxServerMemory\Application.config" -Destination "D:\Vulcan\Tasks\SqlMaxServerMemory\Application.config" -force -Confirm:$false
		Copy-Item "U:\Vulcan_Tasks_SqlMaxServerMemory\LoadConfig.ps1" -Destination "D:\Vulcan\Tasks\SqlMaxServerMemory\LoadConfig.ps1" -force -Confirm:$false
		Copy-Item "U:\Vulcan_Tasks_SqlMaxServerMemory\SQL_SetMaxMemoryForClusters.ps1" -Destination "D:\Vulcan\Tasks\SqlMaxServerMemory\SQL_SetMaxMemoryForClusters.ps1" -force -Confirm:$false
		
		Pop-Location
		Remove-PSDrive U
		
		
	} -Credential $Credential -ArgumentList $Credential,$configurationPath,$domainName,$failoverRoleName
}

















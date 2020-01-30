function enableTcpip
{
	param(
		[string]$Port,
		[System.Management.Automation.PSCredential]$Credential,
		[string]$ServerName,
		[string]$InstanceName
	)
	
	Invoke-Command -ComputerName $ServerName -scriptblock{ 
		param($port,$instanceName)
		try
		{
			[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement") | out-null
			$wmi = new-object ('Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer')  
			$uri = "ManagedComputer[@Name='" + (get-item env:\computername).Value + "']/ServerInstance[@Name='$instanceName']/ServerProtocol[@Name='Tcp']"  
			Write-Host $uri
			$Tcp = $wmi.GetSmoObject($uri)  
			# ManagedComputer[@Name='VDB01A']/ServerInstance[@Name='SQL2016B']/ServerProtocol[@Name='Tcp']
			$Tcp.IsEnabled = $true  
			$TCP2 = $wmi.GetSmoObject($uri + "/IPAddress[@Name='IPAll']")
			$TCP2.IPAddressProperties[1].Value=$port
			$TCP2.IPAddressProperties[0].Value=""
			$Tcp.Alter()  
			$TCP2.IPAddressProperties
		}
		catch
		{
			Write-Host("$(Get-Date):: ERROR `n$(Get-Date):: $($error[0].ToString())`n$(Get-Date):: Line: $($error[0].InvocationInfo.ScriptLineNumber)")
			$global:errorList += ,"$(Get-Date):: ERROR `n$(Get-Date):: $($error[0].ToString())`n$(Get-Date):: Line: $($error[0].InvocationInfo.ScriptLineNumber)`n$(Get-Date):: enableTcpip failed!`n"
			return $false
		}
	} -Credential $Credential -ArgumentList $Port, $InstanceName
	
	return $true
}
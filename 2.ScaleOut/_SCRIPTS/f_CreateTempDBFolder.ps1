function CreateTempDBFolder
{
	param(
		[System.Management.Automation.PSCredential]$Credential,
		[string]$ServerName,
		[string]$tempDbPath
	)
	
	Invoke-Command -ComputerName $ServerName -scriptblock{ 
		param($tempDbPath)
		try
		{
			$domainName = (Get-WmiObject Win32_ComputerSystem).domain

			if(!(Test-Path $tempDbPath))
			{
				New-Item -ItemType directory -Path $tempDbPath
				Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false
				Install-Module -Name NTFSSecurity -Force -Confirm:$false

				Add-NTFSAccess -Path $tempDbPath -Account "$domainName\User4Sql", "$domainName\User4SqlAgent" -AccessRights FullControl
			}
		}
		catch
		{
			Write-Host("$(Get-Date):: ERROR `n$(Get-Date):: $($error[0].ToString())`n$(Get-Date):: Line: $($error[0].InvocationInfo.ScriptLineNumber)")
			$global:errorList += ,"$(Get-Date):: ERROR `n$(Get-Date):: $($error[0].ToString())`n$(Get-Date):: Line: $($error[0].InvocationInfo.ScriptLineNumber)`n$(Get-Date):: CreateTempDBFolder failed!`n"
			return $false
		}
	} -Credential $Credential -ArgumentList $tempDbPath
	
	return $true
}
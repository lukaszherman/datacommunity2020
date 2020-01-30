function InstallSqlInstance
{
	param(
		[System.Management.Automation.PSCredential]$Credential,
		[string]$ServerName,
		[Security.SecureString]$passwordUser4Sql,
		[Security.SecureString]$passwordUser4SqlAgent,
		[string]$configFile,
		[string]$configurationPath,
		[string]$setupPath
	)
	
	Invoke-Command -ComputerName $ServerName -scriptblock{ 
		param(
			[Security.SecureString]$passwordUser4Sql,
			[Security.SecureString]$passwordUser4SqlAgent,
			[string]$configFile,
			[string]$configurationPath,
			[System.Management.Automation.PSCredential]$Credential,
			[string]$setupPath
		)
		try
		{
			Set-Item WSMan:\localhost\Shell\MaxMemoryPerShellMB 2048
			
			New-PSDrive -Name U -PSProvider filesystem -Root ${configurationPath} -Credential $Credential | Out-Null
			Push-Location | Out-Null
			Set-Location 'U:\'
			
			$updatePath = ""
			Write-Host "Test path ""$($setupPath -replace '\\Setup.exe','')\Updates"""
			if(Test-Path "$($setupPath -replace '\\Setup.exe','')\Updates"){$updatePath = '/UpdateEnabled=TRUE /UpdateSource=".\Updates"'}
			
			
			[string]$passwordUser4Sql = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordUser4Sql))
			[string]$passwordUser4SqlAgent = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordUser4SqlAgent))
			
			$installCmd = "$setupPath /Q /SQLSVCPASSWORD='$passwordUser4Sql' /AGTSVCPASSWORD='$passwordUser4SqlAgent' /ConfigurationFile=""$configFile"" /IAcceptSQLServerLicenseTerms $updatePath"
			$installCmd
			 
			Invoke-Expression $installCmd
			
			Pop-Location | Out-Null
			Remove-PSDrive U
		
		}
		catch
		{
			Write-Host("$(Get-Date):: ERROR `n$(Get-Date):: $($error[0].ToString())`n$(Get-Date):: Line: $($error[0].InvocationInfo.ScriptLineNumber)")
			$global:errorList += ,"$(Get-Date):: ERROR `n$(Get-Date):: $($error[0].ToString())`n$(Get-Date):: Line: $($error[0].InvocationInfo.ScriptLineNumber)`n$(Get-Date):: InstallSqlInstance failed!`n"
			return $false
		}
	} -Credential $Credential –Authentication CredSSP -ArgumentList $passwordUser4Sql,$passwordUser4SqlAgent,$configFile,$configurationPath,$Credential,$setupPath
	
	return $true
}
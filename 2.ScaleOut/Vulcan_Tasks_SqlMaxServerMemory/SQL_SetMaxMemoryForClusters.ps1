#Set-ExecutionPolicy RemoteSigned
#cmd /c powershell -executionpolicy bypass -file D:\Vulcan\Tasks\SqlMaxServerMemory\SQL_SetMaxMemoryForClusters.ps1 >> D:\Vulcan\Tasks\SqlMaxServerMemory\SQL_SetMaxMemoryForClusters.log
Push-Location (Split-Path (Get-Variable MyInvocation -Scope Script).Value.MyCommand.Path)

.\LoadConfig.ps1 Application.config 

$running_servs = "running_servs.txt"
$running_servnames = "running_servnames.txt"

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | Out-Null
function cleanup()
{
	del $running_servnames
	del $running_servs
}

Function Send-Mail($subject, $content)
{
	"[$(Get-Date)]:: Mail sent. ($subject)"
	$emailFrom = $appSettings["emailFrom"]
	$emailTo = $appSettings["emailTo"]
	$body = $content

	$smtpServer = $appSettings["SMTPServer"]

	$message = New-Object Net.Mail.MailMessage($emailFrom, $emailTo, $subject, $body)
	$message.IsBodyHTML = $true

	$smtp = new-object Net.Mail.SmtpClient($smtpServer)
	$smtp.Credentials = New-Object System.Net.NetworkCredential($appSettings["SMTPUser"], $appSettings["SMTPPassword"]);

	$smtp.Send($message)
}

$Domain = (Get-WmiObject Win32_ComputerSystem).domain.Split(".")
$EnvName = $Domain[$Domain.Length-2]
$serverName = (Get-WmiObject Win32_ComputerSystem).Name
$srvcount = 1;

$running_srv_cnt = (Get-Service * | where {$_.Name -like '*MSSQL$*'} | where {$_.Status -eq 'Running'}).Length

#Here is where we determine if the # of running instances exceeds the expected # and change maxmem accordingly. 
if ($running_srv_cnt -lt $srvcount)
{
	echo "[$(Get-Date)]:: Less than the expected number of sql server instances are running."
}
elseif ($running_srv_cnt -gt $srvcount)
{
	echo "[$(Get-Date)]:: Failover condition exists... will set maxmem appropriately"
}
else 
{
	echo "[$(Get-Date)]:: Expected number of sql server instances are running - verifying maxmem..."
}

#Set maxmem to right value, always leave ~3gb for the OS. Maxmem should be close to ($maxmem/$running_srv_cnt) 
#$maxmem = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property capacity -Sum | Foreach {"{0}" -f ([math]::round(($_.Sum / 1MB),0))}) - 2000
$maxmem = [Math]::Round(((Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory/ 1MB),2) - 2000
$new_maxmem = [math]::floor($maxmem / $running_srv_cnt)

#The Get-Service cmdlet gets a list of running sql server service names and redirects them to a file.
$runningServices = (Get-Service * | where {$_.Name -like '*MSSQL$*'} | where {$_.Status -eq 'Running'} | Select Name).Name
$runningServices | Out-File running_servs.txt
$allMSSQLServices = (Get-Service * | where {$_.Name -like '*MSSQL$*'} | Select Name)

#We parse through the list of running services using each element of the $sqlgroup array as the search pattern. 
#When a match is found, i.e. a member of the $sqlgroup is found in the file, we set the $servername variable
#and then output the $servername value to another file. This file will contain the sql server instance names
#for running instances. 


$sqlVersion = "2016"

foreach($x in $allMSSQLServices.Name)
{
	$ret = $runningServices | Select-string -SimpleMatch  -Pattern $x -quiet; 
	if ($ret) 
	{
		Switch ($x)
		{
			'MSSQL$SQL2016A' {$servname = ".\SQL${sqlVersion}A"}
			'MSSQL$SQL2016B' {$servname = ".\SQL${sqlVersion}B"}
			'MSSQL$SQL2016C' {$servname = ".\SQL${sqlVersion}C"}
			'MSSQL$SQL2016D' {$servname = ".\SQL${sqlVersion}D"}
			default {$servname = "undetermined"}
		}
		echo $servname >> $running_servnames
	}
	$ret = $null
}

$servlist = Get-Content $running_servnames

#Once we have the $servlist built we can use it to change maxmem for each running server.
foreach ($x in $servlist)
{
	$srv = new-object ("Microsoft.SqlServer.Management.Smo.Server") $x
	if ($srv.ComputerNamePhysicalNetBIOS -ne $null)
	{
		$config = $srv.Configuration
		$running_maxmem = $config.MaxServerMemory.ConfigValue
		if ($running_maxmem -eq $new_maxmem)
		{
			echo "[$(Get-Date)]:: Memory has already been adjusted on $x to $running_maxmem"
		}
		else
		{
			echo "[$(Get-Date)]:: Memory setting of $running_maxmem is incorrect - setting to $new_maxmem";
			$config.ShowAdvancedOptions.ConfigValue = 1
			$config.MaxServerMemory.ConfigValue = $new_maxmem
			$config.Alter()
			echo "[$(Get-Date)]:: Maxmem successfully adjusted on $x to $new_maxmem"
			Send-Mail -subject "[$EnvName][$serverName][$x] SQL MaxServerMemory changed!" `
				-content "[$(Get-Date)]:: Maxmem successfully adjusted on $x to $new_maxmem MB <br \> Server usable memory: $maxmem"
		}
	}
}

cleanup

Pop-Location

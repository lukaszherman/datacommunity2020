
$InstanceName = "SQL14A\SQL2016A"
$recipient = "TuWpiszMaila@vulcan.edu.pl"


Function GetDeadlocks($instanceName)
{
	Write-Host "$(Get-Date):: Gathering deadlocks from $instanceName"
	$query = @"
SELECT TOP 100
	DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()), XEvent.value('(@timestamp)[1]', 'datetime'))        AS event_time,
	XEvent.query('(data/value/deadlock)') AS deadlock_graph
FROM
(
	SELECT CAST(event_data AS XML) as [target_data]
	FROM sys.fn_xe_file_target_read_file('system_health_*.xel',NULL,NULL,NULL)
	WHERE object_name like 'xml_deadlock_report'
) AS [x]
CROSS APPLY target_data.nodes('/event') AS XEventData(XEvent)
--WHERE XEvent.value('(@timestamp)[1]', 'datetime') >= '2019-09-23 15:12:15.393'
ORDER BY event_time DESC
"@

	Import-Module "sqlps" -DisableNameChecking
	$allDeadlocks = Invoke-Sqlcmd -Query $query -ServerInstance $instanceName -MaxCharLength ([int]::MaxValue)

	return $allDeadlocks
}

Function Send-Mail($subject, $content, $attachments, $InstanceName, $recipient)
{
    $Domain = (Get-WmiObject Win32_ComputerSystem).domain.Split(".")
    $EnvName = $Domain[$Domain.Length-2]
    $ComputerName = [System.Net.Dns]::GetHostName()
    $subject = "[$EnvName][$InstanceName] $subject"
	Write-Output "$(Get-Date):: Mail sent. ($subject)"
	$emailFrom = "Adresat@mail.com"
	$emailTo = $recipient 
	$body = $content

	$smtpServer = "smtp.mail.com"
	$message = New-Object Net.Mail.MailMessage($emailFrom, $emailTo, $subject, $body)
	$message.IsBodyHTML = $true
	foreach($attachment in $attachments){$message.Attachments.Add($attachment)}

	$smtp = new-object Net.Mail.SmtpClient($smtpServer)
	$smtp.Credentials = New-Object System.Net.NetworkCredential("admin", "admin1");
	$smtp.Send($message)
}

$allDeadlocks = GetDeadlocks $instanceName # event_time, deadlock_graph

$attachments = @()

foreach($dead in $allDeadlocks)
{
	$dateTime = $dead.event_time.ToString("s").Replace(":","-")
	$instance = $instanceName.Replace("\", "_")
	# Create attachment
	$ct = new-object System.Net.Mime.Contenttype 
	$ct.name = $($instance + "_" + $dateTime + ".xdl")
	$attachments += [System.Net.Mail.Attachment]::CreateAttachmentFromString($dead.deadlock_graph,$ct)
}

$subject = "Deadlocks informations" 
$content = "TOP 100 deadlocks from $InstanceName <br /><br />Save *.xdl files and open in SQL Sentry Plan Explorer."
Send-Mail $subject $content $attachments $InstanceName $recipient



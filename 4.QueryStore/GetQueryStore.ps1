
$InstanceName = "SQL516A\SQL2016A"
$databaseName = "DATABASEabcABC"
$recipient = "komu@wyslac.maila"
$path = "D:\Vulcan\Tasks\QueryStore"

Function GetQueryStore($instanceName, $databaseName)
{
	Write-Host "$(Get-Date):: Gathering QueryStore details from $instanceName $databaseName"
	$query = @"
USE $databaseName
GO

with querystore (sql_text, query_id, sumCPU, sumDuration, sumReads, Plans, count, object_name, type)
AS
(
--CPU time for whole database
SELECT 
MAX(qt.query_sql_text) as sql_text, 
q.query_id, 
-- Microseconds to miliseconds
CAST(SUM(rs.avg_cpu_time*rs.count_executions)/1000 AS decimal(16,0)) as sumCPU, -- CPU
CAST(SUM(rs.avg_duration*rs.count_executions)/1000 AS decimal(16,0)) as sumDuration, -- Duration
CAST(SUM(rs.avg_logical_io_reads*rs.count_executions)/1000 AS decimal(16,0)) as sumReads, -- Logical reads
COUNT(1) as Plans, 
SUM(rs.count_executions) AS Count,
max(so.name) as object_name, 
max(so.type) as type
FROM
sys.query_store_query_text qt JOIN
sys.query_store_query q ON qt.query_text_id = q.query_text_id JOIN
sys.query_store_plan p ON q.query_id = p.query_id JOIN
sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id JOIN
sys.query_store_runtime_stats_interval rsi ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id LEFT JOIN
sysobjects so on so.id = q.object_id
WHERE rsi.start_time >= DATEADD(HOUR, -24, GETUTCDATE())
group by q.query_id
)
SELECT  replace( replace(replace(replace(sql_text, char(13), ''), char(10), ''), char(9), ''), char(13) + char(10), '') AS sql_text, query_id, sumCPU, sumDuration, sumReads, plans, count, object_name, type
,FORMAT((sumCPU / (select sum(sumCPU) from querystore)), 'P3') AS CPU_Percent 
,FORMAT((sumDuration / (select sum(sumDuration) from querystore)), 'P3') AS Duration_Percent 
,FORMAT((sumReads / (select sum(sumReads) from querystore)), 'P3') AS Reads_Percent 
FROM querystore
ORDER BY (sumCPU / (select sum(sumCPU) from querystore)) DESC
"@

	Import-Module "sqlps" -DisableNameChecking
	$queryStoreDetails = Invoke-Sqlcmd -Query $query -ServerInstance $instanceName -MaxCharLength ([int]::MaxValue) -QueryTimeout 3600

	return $queryStoreDetails
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

function Out-Excel
{
  param($Path = "$env:temp$(Get-Date -Format yyyyMMddHHmmss).csv")
  $input | Export-CSV -Path $Path -UseCulture -Encoding UTF8 -NoTypeInformation
}

$queryStoreDetails = GetQueryStore $instanceName $databaseName

if(!(Test-Path($path))) {New-Item -ItemType Directory -path $path | Out-Null}

$csvPath = "$path\QueryStore_${databaseName}_$(Get-Date -Format yyyyMMddHHmmss).csv"
$zipPath = "$path\QueryStore_${databaseName}_$(Get-Date -Format yyyyMMddHHmmss).zip"
$queryStoreDetails | Sort-Object -Property CPU_Percent -Descending | SELECT sql_text, sumCPU, sumDuration, sumReads, CPU_Percent, Duration_Percent, Reads_Percent -First 1000 | Out-Excel -Path $csvPath
Compress-Archive -Path $csvPath -CompressionLevel Optimal -DestinationPath $zipPath

$subject = "QueryStore informations" 
$content = "Please refer to the attached spread sheet for TOP 1000 queries report for $databaseName for last 24 hours. Colmuns: sql_text, query_id, sumCPU, sumDuration, sumReads, Plans, count, object_name, type, CPU_Percent, Duration_Percent, Reads_Percent"
Send-Mail $subject $content $zipPath $InstanceName $recipient



$o = Get-WmiObject -Class Win32_volume -Filter 'DriveType=5' | Select-Object -First 1 |	Set-WmiInstance -Arguments @{DriveLetter='e:'}
Write-Output ("$(Get-Date)::$($env:computername):: CD-ROM {0}" -f $o.DriveLetter)
Write-Output ("$(Get-Date)::$($env:computername):: New-Partition") 
if (-not (Test-Path D:\)) {
	New-Partition -DiskNumber 0 -UseMaximumSize -DriveLetter D -ErrorAction SilentlyContinue
	if(Get-Partition -DriveLetter D -ErrorAction SilentlyContinue) 
	{
		Format-Volume -Partition (Get-Partition -PartitionNumber 5) -FileSystem NTFS -NewFileSystemLabel "Data" -AllocationUnitSize 65536 -Confirm:$false -ErrorAction SilentlyContinue
	}
}
if (-not (Test-Path D:\)) {
	new-volume -DiskNumber 1 -FriendlyName Data -FileSystem NTFS -AccessPath D: -AllocationUnitSize 65536 -ErrorAction SilentlyContinue > C:\NewVolume.log
}

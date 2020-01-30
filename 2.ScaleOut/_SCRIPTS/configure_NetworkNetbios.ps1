$adapters=(gwmi win32_networkadapterconfiguration )
Foreach ($adapter in $adapters){
  Write-Host $adapter
  $adapter.settcpipnetbios(2)
}

netsh advfirewall firewall set rule group="Windows Management Instrumentation (WMI)" new enable=yes
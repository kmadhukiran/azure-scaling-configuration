function Set-AscAzureVmZabbixMaintenanceStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$vmName,
        [Parameter(Mandatory = $true)][ValidateSet("VM deallocated", "VM running")][string]$state,
        [Parameter(Mandatory = $true)][string]$token
    );
    

    $zabbixHostGroup = Get-AscZabbixHostGroup -token $token -groupName "Azure Automation maintenance";
    $zabbixHost = Get-AscZabbixHost -token $token -hostName $vmName;


    switch ($state)
    {
        "VM deallocated"
        {
            Add-AscZabbixHostGroupHost -token $token -hostGroupId $zabbixHostGroup.groupid -hostId $zabbixHost.hostid;
        }
        "VM running"
        {
            Remove-AscZabbixHostGroupHost -token $token -hostGroupId $zabbixHostGroup.groupid -hostId $zabbixHost.hostid;
        }
    }
}
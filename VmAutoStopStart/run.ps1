# Input bindings are passed in via param block.
#
# version: #{GitVersion_InformationalVersion}#
#
param (
    $timer
);


# The 'IsPastDue' porperty is 'true' when the current function invocation is later than scheduled.
if ($timer.IsPastDue) {
    Write-Host "PowerShell timer is running late.";
}

# Write an information log with the current time.
Write-Host "Function triggered. TIME: $((Get-Date).ToUniversalTime())";


#region Reading app settings
$appId = $env:VmAutoStopStart_appId;
$secret = $env:VmAutoStopStart_appSecret;
$tenant = $env:VmAutoStopStart_tenantId;
$zabbixUserName = $env:zabbixUserName;
$zabbixUserPassword = $env:zabbixUserPassword;
#endregion /Reading app settings


Write-Output "Logging to Azure.";
$azureCredentials = New-Object System.Management.Automation.PSCredential ($appId, $(ConvertTo-SecureString $secret -AsPlainText -Force));
Connect-AzAccount -Tenant $tenant -Credential $azureCredentials -ServicePrincipal | Out-Null;
Write-Output "Logging to Zabbix.";
$zabbixCrenetials = New-Object System.Management.Automation.PSCredential ($zabbixUserName, $(ConvertTo-SecureString $zabbixUserPassword -AsPlainText -Force));
$zabbixToken = Connect-AscZabbix -credential $zabbixCrenetials;


$ignoredVmStates = @(
    "VM deallocating",
    "VM starting"
);


#region Reading registry
$registry = Get-Content .\registry\azure-vms.jsonc | ConvertFrom-Json;
#endregion /Reading registry


# This array is used store a list of VMs which will be started and Zabbix Maintenance must be disabled.
# We want to wait until they're started up and only then disable Maintenance.
# If we wont wait - Zabbix Maintenance will be disabled instantly and Zabbix will start pinging them and will raise alerts.
$disableZabbixMaintenance = @();

#region Processing VMs
foreach ($item in $registry)
{
    Write-Output "Processing the '$($item.name)'.";
    $vm = Get-AzVM -Name $item.name -Status;
    #$vmStatus = $vm.Statuses | ?{$_.Code -match "PowerState"} | Select-Object -ExpandProperty DisplayStatus;


    #region Get current date/time and convert to $scheduleTimeZone
    $stateConfig = $item.schedule | ConvertFrom-Json;
    $startTime = Get-Date;
    Write-Output "Azure local time: $startTime.";
    $scheduleTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($item.scheduleTimeZone);
    Write-Output "Time zone to convert to: $scheduleTimeZone.";
    $newTime = [System.TimeZoneInfo]::ConvertTime($startTime, $scheduleTimeZone);
    Write-Output "Converted time: $newTime.";
    $startTime = $newTime;
    #endregion /Get current date/time and convert to $scheduleTimeZone

    #region Get current day of week, based on converted start time
    $currentDayOfWeek = [int]($startTime).DayOfWeek;
    Write-Output "Current day of week: $currentDayOfWeek.";
    #endregion /Get current day of week, based on converted start time

    #region Get the schedule for the current day of week
    $dayObjects = $stateConfig | `
        Where-Object {$_.WeekDays -contains $currentDayOfWeek } | `
        Select-Object State, `
            @{Name="StartTime"; Expression = {[datetime]::ParseExact(($startTime.ToString("yyyy:MM:dd")+":"+$_.StartTime),"yyyy:MM:dd:HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)}}, `
            @{Name="StopTime"; Expression = {[datetime]::ParseExact(($startTime.ToString("yyyy:MM:dd")+":"+$_.StopTime),"yyyy:MM:dd:HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)}};
    #endregion /Get the schedule for the current day of week


    if ($dayObjects) # Schedule found for this day
    {
        # Get the schedule for the current time. If there is more than one available, pick the first
        $matchingObject = $dayObjects | ?{ ($startTime -ge $_.StartTime) -and ($startTime -lt $_.StopTime) } | Select-Object -First 1;
        if ($matchingObject)
        {
            Write-Output "Scaling schedule found. Checking if current VM state is desired.";
            if (($vm.PowerState -ne $matchingObject.state) -and ($vm.PowerState -notin $ignoredVmStates))
            #if ($vm.PowerState)
            {
                Write-Output "VM is not in the desired state ($($vm.PowerState)). Changing to '$($matchingObject.state)'.";
                Set-AscAzureVmPowerStatus -vm $vm -state $matchingObject.state;

                if ($matchingObject.state -eq "VM deallocated")
                {
                    Write-Output "Updating Zabbix Maintenance.";
                    Set-AscAzureVmZabbixMaintenanceStatus -vmName $vm.Name -token $zabbixToken -state $matchingObject.state;
                }
                else { $disableZabbixMaintenance += $vm; }
            }
            elseif ($vm.PowerState -in $ignoredVmStates)
            {
                Write-Output "VM state is '$($vm.PowerState)'. Skipping.";
            }
            else
            {
                Write-Output "Current VM state matches the schedule ($($matchingObject.state)). Skipping. Updating Zabbix Maintenance.";
                Set-AscAzureVmZabbixMaintenanceStatus -vmName $vm.Name -token $zabbixToken -state $matchingObject.state;
            }
        }
        else # Schedule not found for current time
        {
            Write-Output "No matching schedule time slot for this time found. Checking if current VM state is 'default'.";
            if (($vm.PowerState -ne $item.defaultState) -and ($vm.PowerState -notin $ignoredVmStates))
            {
                Write-Output "VM is not in the default state ($($vm.PowerState)). Changing to '$($item.defaultState)'.";
                Set-AscAzureVmPowerStatus -vm $vm -state $item.defaultState;

                if ($item.defaultState -eq "VM deallocated")
                {
                    Write-Output "Updating Zabbix Maintenance.";
                    Set-AscAzureVmZabbixMaintenanceStatus -vmName $vm.Name -token $zabbixToken -state $item.defaultState;
                }
                else { $disableZabbixMaintenance += $vm; }
            }
            elseif ($vm.PowerState -in $ignoredVmStates)
            {
                Write-Output "VM state is '$($vm.PowerState)'. Skipping.";
            }
            else
            {
                Write-Output "Current VM state matches the default ($($item.defaultState)). Skipping. Updating Zabbix Maintenance.";
                Set-AscAzureVmZabbixMaintenanceStatus -vmName $vm.Name -token $zabbixToken -state $item.defaultState | Out-Null;
            }
        }
    }
    else # Schedule not found for this day
    {
        Write-Output "No matching scaling schedule for this day found. Checking if current VM state is 'default'.";
        if (($vm.PowerState -ne $item.defaultState) -and ($vm.PowerState -notin $ignoredVmStates))
        {
            Write-Output "VM is not in the default state ($($vm.PowerState)). Changing to '$($item.defaultState)'.";
            Set-AscAzureVmPowerStatus -vm $vm -state $item.defaultState;

            if ($item.defaultState -eq "VM deallocated")
            {
                Write-Output "Updating Zabbix Maintenance.";
                Set-AscAzureVmZabbixMaintenanceStatus -vmName $vm.Name -token $zabbixToken -state $item.defaultState | Out-Null;
            }
            else { $disableZabbixMaintenance += $vm; }
        }
        elseif ($vm.PowerState -in $ignoredVmStates)
        {
            Write-Output "VM state is '$($vm.PowerState)'. Skipping.";
        }
        else
        {
            Write-Output "Current VM state matches the default ($($item.defaultState)). Skipping. Updating Zabbix Maintenance.";
            Set-AscAzureVmZabbixMaintenanceStatus -vmName $vm.Name -token $zabbixToken -state $item.defaultState | Out-Null;
        }
    }
}
#endregion /Processing VMs


#region Waiting for jobs to finish
try
{
    Write-Output "Waiting for jobs to finish (count = $($(Get-Job).Count)).";
    Get-Job | Wait-Job -ErrorAction Stop;
}
catch
{
    Write-Error $_;
}
#endregion /Waiting for jobs to finish


#region Disable Zabbix Maintenance if any
if ($disableZabbixMaintenance.count -gt 0)
{
    Write-Output "Sleeping for 5 minutes.";
    Start-Sleep -Seconds 300;
}
foreach ($vm in $disableZabbixMaintenance)
{
    Write-Output "Updating Zabbix Maintenance for '$($vm.Name)'.";
    Set-AscAzureVmZabbixMaintenanceStatus -vmName $vm.Name -token $zabbixToken -state "VM running";
}
#endregion /Disable Zabbix Maintenance if any


#region Checking for failed jobs
$failedJobs = Get-Job | ?{$_.state -eq "Failed"};
if ($failedJobs)
{
    Write-Error "Errors while executing 'VmAutoStopStart: ...'";
    Write-Error $(Get-Job | Receive-Job);
}
#endregion /Checking for failed jobs


Write-Output "Removing jobs.";
Get-Job | Remove-Job -ErrorAction Stop -Force;


Write-Output "Disconnecting from Zabbix.";
Disconnect-AscZabbix -token $zabbixToken;


Write-Output "Function run complete.";
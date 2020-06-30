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
$appId = $env:SqlDatabaseAutoscale_appId;
$secret = $env:SqlDatabaseAutoscale_appSecret;
$tenant = $env:SqlDatabaseAutoscale_tenantId;
#endregion /Reading app settings


Write-Output "Logging to Azure.";
$azureCredentials = New-Object System.Management.Automation.PSCredential ($appId, $(ConvertTo-SecureString $secret -AsPlainText -Force));
Connect-AzAccount -Tenant $tenant -Credential $azureCredentials -ServicePrincipal  | Out-Null;


#region Reading registry
$registry = Get-Content .\registry\azure-sqlDb.jsonc | ConvertFrom-Json;
#endregion /Reading registry


#region Processing registry items
foreach ($item in $registry)
{
    #Wait-Debugger
    Write-Output "Processing the '$($item.name)'.";

    Write-Output "Switching to the Azure Subscription: $($item.subscriptionId).";
    Select-AzSubscription -Subscription $item.subscriptionId | Out-Null;
    $sqlDatabase = Get-AzSqlDatabase -Name $item.name -ServerName $item.server -ResourceGroupName $item.resourceGroup;

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
        Select-Object `
            Edition, `
            Tier, `
            @{Name="StartTime"; Expression = {[datetime]::ParseExact(($startTime.ToString("yyyy:MM:dd")+":"+$_.StartTime),"yyyy:MM:dd:HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)}}, `
            @{Name="StopTime"; Expression = {[datetime]::ParseExact(($startTime.ToString("yyyy:MM:dd")+":"+$_.StopTime),"yyyy:MM:dd:HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)}};
    #endregion /Get the schedule for the current day of week

    if ($dayObjects) # Schedule found for this day
    {
        # Get the schedule for the current time. If there is more than one available, pick the first
        $matchingObject = $dayObjects | ?{ ($startTime -ge $_.StartTime) -and ($startTime -lt $_.StopTime) } | Select-Object -First 1;
        if ($matchingObject)
        {
            Write-Output "Scaling schedule found. Checking if current SQL database SKU state is desired.";
            if ($sqlDatabase.CurrentServiceObjectiveName -ne $matchingObject.Tier -or $sqlDatabase.Edition -ne $matchingObject.Edition)
            {
                Write-Output "SQL database is not in the desired state ($($sqlDatabase.Edition)\$($sqlDatabase.CurrentServiceObjectiveName)). Changing to '$($matchingObject.Edition)\$($matchingObject.Tier)'.";
                $sqlDatabase | Set-AzSqlDatabase -Edition $matchingObject.Edition -RequestedServiceObjectiveName $matchingObject.Tier;
            }
            else
            {
                Write-Output "Current SQL database state matches the schedule ($($matchingObject.Edition)\$($matchingObject.Tier)). Skipping.";
            }
        }
        else # Schedule not found for current time
        {
            Write-Output "No matching schedule time slot for this time found. Checking if current SQL database state is 'default'.";
            if ($sqlDatabase.CurrentServiceObjectiveName -ne $item.defaultTier -or $sqlDatabase.Edition -ne $item.defaultEdition)
            {
                Write-Output "SQL database is not in the default state ($($sqlDatabase.Edition)\$($sqlDatabase.CurrentServiceObjectiveName)). Changing to '$($item.defaultEdition)\$($item.defaultTier)'.";
                $sqlDatabase | Set-AzSqlDatabase -Edition $item.defaultEdition -RequestedServiceObjectiveName $item.defaultTier;
            }
            else
            {
                Write-Output "Current SQL database state matches the default ($($item.defaultEdition)\$($item.defaultTier)). Skipping.";
            }
        }
    }
    else # Schedule not found for this day
    {
        Write-Output "No matching scaling schedule for this day found. Checking if current SQL database state is 'default'.";
        if ($sqlDatabase.CurrentServiceObjectiveName -ne $item.defaultTier -or $sqlDatabase.Edition -ne $item.defaultEdition)
        {
            Write-Output "SQL database is not in the default state ($($sqlDatabase.Edition)\$($sqlDatabase.CurrentServiceObjectiveName)). Changing to '$($item.defaultEdition)\$($item.defaultTier)'.";
            $sqlDatabase | Set-AzSqlDatabase -Edition $item.defaultEdition -RequestedServiceObjectiveName $item.defaultTier;
        }
        else
        {
            Write-Output "Current SQL database state matches the default ($($item.defaultEdition)\$($item.defaultTier)). Skipping.";
        }
    }
}
#endregion /Processing registry items


Write-Output "Function run complete.";
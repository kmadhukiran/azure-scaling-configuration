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
$appId = $env:PowerBiEmbeddedAutoscale_appId;
$secret = $env:PowerBiEmbeddedAutoscale_appSecret;
$tenant = $env:PowerBiEmbeddedAutoscale_tenantId;
#endregion /Reading app settings


Write-Output "Logging to Azure.";
$azureCredentials = New-Object System.Management.Automation.PSCredential ($appId, $(ConvertTo-SecureString $secret -AsPlainText -Force));
Connect-AzAccount -Tenant $tenant -Credential $azureCredentials -ServicePrincipal  | Out-Null;


#region Reading registry
$registry = Get-Content .\registry\azure-powerbi.jsonc | ConvertFrom-Json;
#endregion /Reading registry


#region Processing registry items
foreach ($item in $registry)
{
    #Wait-Debugger
    Write-Output "Processing the '$($item.name)'.";

    Write-Output "Switching to the Azure Subscription: $($item.subscriptionId).";
    Select-AzSubscription -Subscription $item.subscriptionId | Out-Null;
    $powerBi = Get-AzPowerBIEmbeddedCapacity -Name $item.name;

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
        Select-Object Sku, `
            @{Name="StartTime"; Expression = {[datetime]::ParseExact(($startTime.ToString("yyyy:MM:dd")+":"+$_.StartTime),"yyyy:MM:dd:HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)}}, `
            @{Name="StopTime"; Expression = {[datetime]::ParseExact(($startTime.ToString("yyyy:MM:dd")+":"+$_.StopTime),"yyyy:MM:dd:HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)}};
    #endregion /Get the schedule for the current day of week

    if ($dayObjects) # Schedule found for this day
    {
        # Get the schedule for the current time. If there is more than one available, pick the first
        $matchingObject = $dayObjects | ?{ ($startTime -ge $_.StartTime) -and ($startTime -lt $_.StopTime) } | Select-Object -First 1;
        if ($matchingObject)
        {
            Write-Output "Scaling schedule found. Checking if current PowerBi Embedded SKU state is desired.";
            if ($powerBi.Sku -ne $matchingObject.Sku)
            {
                Write-Output "PowerBi Embedded is not in the desired state ($($powerBi.Sku)). Changing to '$($matchingObject.Sku)'.";
                Update-AzPowerBIEmbeddedCapacity -Name $item.name -sku $matchingObject.Sku;
            }
            else
            {
                Write-Output "Current PowerBi Embedded state matches the schedule ($($matchingObject.Sku)). Skipping.";
            }
        }
        else # Schedule not found for current time
        {
            Write-Output "No matching schedule time slot for this time found. Checking if current PowerBi Embedded state is 'default'.";
            if ($powerBi.Sku -ne $item.defaultSku)
            {
                Write-Output "PowerBi Embedded is not in the default state ($($powerBi.Sku)). Changing to '$($item.defaultSku)'.";
                Update-AzPowerBIEmbeddedCapacity -Name $item.name -sku $item.defaultSku;
            }
            else
            {
                Write-Output "Current PowerBi Embedded state matches the default ($($item.defaultSku)). Skipping.";
            }
        }
    }
    else # Schedule not found for this day
    {
        Write-Output "No matching scaling schedule for this day found. Checking if current PowerBi Embedded state is 'default'.";
        if ($powerBi.Sku -ne $item.defaultSku)
        {
            Write-Output "PowerBi Embedded is not in the default state ($($powerBi.Sku)). Changing to '$($item.defaultSku)'.";
            Update-AzPowerBIEmbeddedCapacity -Name $item.name -sku $item.defaultSku;
        }
        else
        {
            Write-Output "Current PowerBi Embedded state matches the default ($($item.defaultSku)). Skipping.";
        }
    }
}
#endregion /Processing registry items


Write-Output "Function run complete.";
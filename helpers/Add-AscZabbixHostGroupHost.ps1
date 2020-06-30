function Add-AscZabbixHostGroupHost {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$token,
        [Parameter(Mandatory = $false)][string]$uri = "https://zabbix.domain.local",
        [Parameter(Mandatory = $true)][string]$hostGroupId,
        [Parameter(Mandatory = $true)][string]$hostId
    );


    try 
    {
        $params = @{
            body = @{
                "jsonrpc" = "2.0";
                "method" = "hostgroup.massadd";
                "params" = @{
                    "groups" = @(
                        $hostGroupId
                    );
                    "hosts" = @(
                        $hostId
                    );
                };
                "id" = 1;
                "auth" = $token;
            } | ConvertTo-Json;
            uri = "$uri/api_jsonrpc.php";
            headers = @{"Content-Type" = "application/json"};
            method = "Post";
        };
        
        $result_json = Invoke-WebRequest @params -UseBasicParsing -Verbose:$false -ErrorAction Stop;
        $result_object = $result_json | ConvertFrom-Json -ErrorAction Stop;
    }
    catch 
    {
        Write-Error "Error while trying to add Zabbix Host to HostGroup.";
        Write-Error $_;
    }


    if ($result_object.error)
    {
        Write-Error $("***  Error: " + $result_object.error.message + " " + $result_object.error.data);
    }
    else
    {
        Write-Verbose "Successfully added Zabbix Host to HostGroup.";
        return $result_object.result;
    }
}
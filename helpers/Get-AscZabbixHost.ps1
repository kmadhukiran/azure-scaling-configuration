function Get-AscZabbixHost {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$token,
        [Parameter(Mandatory = $false)][string]$uri = "https://zabbix.domain.local",
        [Parameter(Mandatory = $true)][string]$hostName
    );
    

    try 
    {
        Write-Verbose "Getting Zabbix host object for '$hostName'.";
        
        $params = @{
            body = @{
                "jsonrpc" = "2.0";
                "method" = "host.get";
                "params" = @{
                    "filter" = @{
                        "host" = $hostName;
                    };
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
        Write-Error "Error while trying to get Zabbit host object for '$hostName'.";
        Write-Error $_;
    }


    if ($result_object.error)
    {
        Write-Error $("***  Error: " + $result_object.error.message + " " + $result_object.error.data);
    }
    else
    {
        Write-Verbose "Successfully fetched host object '$hostName' from Zabbix.";
        return $result_object.result;
    }
}
function Get-AscZabbixHostGroup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$token,
        [Parameter(Mandatory = $false)][string]$uri = "https://zabbix.domain.local",
        [Parameter(Mandatory = $true)][string]$groupName
    );


    try 
    {
        $params = @{
            body =  @{
                jsonrpc = "2.0";
                method = "hostgroup.get";
                params = @{
                    output = "extend"
                    selectHosts = @(
                        "hostid",
                        "host"
                    );
                    filter = @{
                        name = $groupName;
                    };
                }
                id = 1;
                auth = $token;
            } | ConvertTo-Json -Depth 10;
            uri = "$uri/api_jsonrpc.php";
            headers = @{"Content-Type" = "application/json"};
            method = "Post";
        };

        $result_json = Invoke-WebRequest @params -UseBasicParsing -Verbose:$false -ErrorAction Stop;
        $result_object = $result_json | ConvertFrom-Json -ErrorAction Stop;
    }
    catch
    {
        Write-Error "Error while getting HostGroup from Zabbix.";
        Write-Error $_;
    }


    if ($result_object.error)
    {
        Write-Error $("***  Error: " + $result_object.error.message + " " + $result_object.error.data);
    }
    else
    {
        return $result_object.result;
    }
}
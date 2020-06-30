function Disconnect-AscZabbix {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$token,
        [Parameter(Mandatory = $false)][string]$uri = "https://zabbix.domain.local"
    );
    
    
    try 
    {
        Write-Verbose "Logging out from Zabbix.";
        $params = @{
            body = @{
                "jsonrpc" = "2.0";
                "method" = "user.logout";
                "params" = @();
                "id" = 1;
                "auth" = $token;
            } | ConvertTo-Json;
            uri = "$uri/api_jsonrpc.php";
            headers = @{
                "Content-Type" = "application/json"
            };
            method  = "Post";
        };
        
        $result_json = Invoke-WebRequest @params -UseBasicParsing -Verbose:$false -ErrorAction Stop;
        $result_object = $result_json | ConvertFrom-Json -ErrorAction Stop;
    }
    catch
    {
        Write-Error "Error while trying logout from Zabbix.";
        Write-Error $_;
    }
    

    if ($result_object.error)
    {
        Write-Error $("***  Error: " + $result_object.error.message + " " + $result_object.error.data);
    }
    else
    {
        Write-Verbose "Successfully logged out from Zabbix.";
        return $result_object.result;
    }
}
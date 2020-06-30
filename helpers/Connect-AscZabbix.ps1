function Connect-AscZabbix {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)][string]$uri = "https://zabbix.domain.local",
        [Parameter(Mandatory = $true)][pscredential]$credential
    );
    

    try 
    {
        Write-Verbose "Logging to Zabbix.";
        $params = @{
            body = @{
                "jsonrpc" = "2.0";
                "method" = "user.login";
                "params" = @{
                    "user" = $credential.UserName;
                    "password" = $credential.GetNetworkCredential().Password;
                };
                "id" = 1;
                "auth" = $null;
            } | ConvertTo-Json -Depth 10;
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
        Write-Error "Error while trying to get Zabbix authorization token.";
        Write-Error $_;
    }
    

    if ($result_object.error)
    {
        Write-Error $("***  Error: " + $result_object.error.message + " " + $result_object.error.data);
    }
    else
    {
        Write-Verbose "Successfully logged to Zabbix.";
        return $result_object.result;
    }
}
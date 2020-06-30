function Set-AscAzureVmPowerStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][Microsoft.Azure.Commands.Compute.Models.PSVirtualMachineListStatus]$vm,
        [Parameter(Mandatory = $true)][ValidateSet("VM deallocated", "VM running")][string]$state
    );


    switch ($state)
    {
        "VM deallocated"
        {
            $vm | Stop-AzVm -AsJob -Force;
        }
        "VM running"
        {
            $vm | Start-AzVM -AsJob;
        }
    }
}
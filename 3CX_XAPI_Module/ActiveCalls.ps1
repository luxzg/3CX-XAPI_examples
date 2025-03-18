# ActiveCalls.ps1
# swagger specs : /ActiveCalls
#	source: https://github.com/luxzg/3CX-XAPI_examples
#	by Luka Pribanić Lux, 2025-03-17

function Get-ActiveCalls {
# Set default parameters
param(
    [Parameter(Mandatory,
		HelpMessage="Provide API user/client ID as string")]
		[string]$user,								# = "test",
    [Parameter(Mandatory,
		HelpMessage="Provide API key/secret as string")]
		[string]$key,								# = "AbCdEfGh123456IjKlMnOp7890rStUvZ",
    [Parameter(Mandatory,
		HelpMessage="Provide PBX URL such as https://YourSubdomainHere.3cx.eu:5001")]
		[string]$url,								# = "https://YourSubdomainHere.3cx.eu:5001",
    [Parameter(Mandatory,
		HelpMessage="Provide number as integer for amount of records to fetch")]
		[int]$top,									# = 100000,
    [Parameter(Mandatory,
		HelpMessage="Provide number as integer for amount of records to skip")]
		[int]$skip									# = 0
)

# Check if PowerShell version is <=5.1 or >=7.5, store major version, otherwise fail
$pscheck = Test-PowerShellModuleVersion

# Fetch XAPI token
$token = Get-XAPIToken -url $url -user $user -key $key

# Define ActiveCalls URI ; prefered order of parameters: $search $filter $count $orderby $skip $top $expand $select $format
$FullURI = "$url/xapi/v1/ActiveCalls?`$count=true&`$orderby=EstablishedAt asc&`$skip=$skip&`$top=$top"

# Fetch data from URI, limit progressbar length to MaxSeconds, two paths depending on PowerShell version 5 or 7
$response = Invoke-XAPIRequestWithProgress -uri $FullURI -token $token -MaxSeconds 180 -Activity "Fetching data from XAPI..." -pscheck $pscheck

# Check response data, count records, warn if something is wrong
Test-Response -data $response

# Show sample data, using columns for select
$columns = @('Id', 'Caller', 'Callee', 'Status', 'LastChangeStatus', 'EstablishedAt', 'ServerNow')
Show-Sample -data $response -columns $columns

}
# Export function for use in the module
Export-ModuleMember -Function Get-ActiveCalls
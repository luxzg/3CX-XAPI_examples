# fetch_call_history.ps1

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
		HelpMessage="Provide ISO 8601 Zulu date/time format: YYYY-MM-DDTHH:mm:ssZ")]
		[string]$from,								# = "2024-12-01T00:00:00Z",	# Use ISO 8601 Zulu time format
    [Parameter(Mandatory,
		HelpMessage="Provide ISO 8601 Zulu date/time format: YYYY-MM-DDTHH:mm:ssZ")]
		[string]$to,								# = "2024-12-31T23:59:59Z",	# Use ISO 8601 Zulu time format
    [Parameter(Mandatory,
		HelpMessage="Provide extension number of queue as string")]
		[string]$queueDns = "",						# Example queueDns is extension number eg "1234"
	[string]$waitInterval = "0:00:0",				# Example waitInterval (in seconds)
    [Parameter(Mandatory,
		HelpMessage="Provide number as integer for amount of records to fetch")]
		[int]$top,									# = 100000,
    [Parameter(Mandatory,
		HelpMessage="Provide number as integer for amount of records to skip")]
		[int]$skip,									# = 0,
    [switch]$help
)

Import-Module "$PSScriptRoot/Modules/CommonFunctions.psm1" -Force
Import-Module "$PSScriptRoot/Modules/DateTimeFunctions.psm1" -Force

# Format paths
$paths = Get-ScriptPaths -MyInvocation $MyInvocation -from $from -to $to -top $top -skip $skip

# Show help if invoked
if ($help) {
    Write-Host @"
	
USAGE:
    $($paths.ScriptDir)\$($paths.ScriptName) -user "test" -key "your_client_secret" -url "https://YourSubdomainHere.3cx.eu:5001" -from "YYYY-MM-DDTHH:MM:SSZ" -to "YYYY-MM-DDTHH:MM:SSZ" -top 100000 -skip 0 -queuedns 1234

EXAMPLES:
    $($paths.ScriptDir)\$($paths.ScriptName) -user "test" -key "abc123" -url "https://example.3cx.eu:5001" -from "2025-02-01T00:00:00Z" -to "2025-02-28T23:59:59Z" -top 50000 -skip 1000 -queuedns 4321
	$($paths.ScriptDir)\$($paths.ScriptName) -user "admin" -key "xyz456" -url "https://yourpbx.3cx.eu:5001" -from "2024-12-01T00:00:00-01:00" -to "2024-12-31T23:59:59-01:00" -top 200000 -skip 0 -queuedns 1111

The '-queuedns' parameter is required and must be equal to extension number of the requested queue.
"@
Show-HelpNotes
    exit 0
}

# Run only on PowerShell 5.x until I can fix date/time formatting for PS 7.x
Confirm-PowerShellModuleVersion -MinMajorVersion 5

# Fetch XAPI token
$token = Get-XAPIToken -url $url -user $user -key $key

# Fix date/time if user provided alternative format without time, with timezone suffix, or similar
$from = Convert-IsoDateTimeToZulu($from)
$to = Convert-IsoDateTimeToZulu($to)

# Define ReportAbandonedQueueCalls URI ; prefered order of parameters: $search $filter $count $orderby $skip $top $expand $select $format
$FullURI = "$url/xapi/v1/ReportAbandonedQueueCalls/Pbx.GetAbandonedQueueCallsData(periodFrom=$from,periodTo=$to,queueDns='$queueDns',waitInterval='$waitInterval')?`$count=true&`$orderby=CallTimeForCsv asc&`$skip=$skip&`$top=$top"

# Fetch data from URI, limit progressbar length to MaxSeconds
$response = Invoke-XAPIRequestWithProgress -uri $FullURI -token $token -MaxSeconds 180 -Activity "Fetching data from XAPI..."

# Check response data, count records, warn if something is wrong
Test-Response -data $response

# Add new formatted columns, with progress bar functionality
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "WaitTime" -NewColumn "WaitTime (text)" -Formatter { param($colValue) Convert-IsoDurationToHumanReadable $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "WaitTime" -NewColumn "WaitTime (seconds)" -Formatter { param($colValue) Convert-IsoDurationToSeconds $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "WaitTime" -NewColumn "WaitTime (hh:mm:ss)" -Formatter { param($colValue) Convert-IsoDurationToSecondsToExcelTimeValue $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "CallTimeForCsv" -NewColumn "StartLocalDate" -Formatter { param($colValue) Convert-IsoDateTimeToLocalDate $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "CallTimeForCsv" -NewColumn "StartLocalTime" -Formatter { param($colValue) Convert-IsoDateTimeToLocalTime $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "CallTimeForCsv" -NewColumn "DayOfWeek" -Formatter { param($colValue) Convert-IsoDateTimeToDayOfWeek $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "CallTimeForCsv" -NewColumn "DayOfWeekCroatian" -Formatter { param($colValue) Convert-IsoDateTimeToDayOfWeekCro $colValue }

Complete-ProgressBar -Activity "Processing records"

# Show sample data, using columns for select
$columns = @('CallTimeForCsv', 'CallerId', 'StartLocalDate', 'ExtensionDisplayName', 'QueueDisplayName', 'WaitTime (text)', 'WaitTime (seconds)', 'WaitTime (hh:mm:ss)', 'StartLocalTime', 'DayOfWeek', 'DayOfWeekCroatian')
Show-Sample -data $response -columns $columns

# Export results to CSV & XLSX (with rename/overwrite prompt if file exists)
$csvFinalPath = Export-DataToCSV -data $response.value -csvPath $paths.CsvPath
$excelFinalPath = Export-DataToExcel -data $response.value -excelPath $paths.ExcelPath -ColumnFormats @{ 'StartLocalDate' = 'yyyy-mm-dd' ; 'WaitTime (hh:mm:ss)' = 'hh:mm:ss' }

# Test if export of CSV and/or Excel was completed, and inform user
Test-ExportResults -csv $csvFinalPath -excel $excelFinalPath

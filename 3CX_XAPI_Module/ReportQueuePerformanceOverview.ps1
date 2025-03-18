# ReportQueuePerformanceOverview.ps1
# swagger specs : /ReportQueuePerformanceOverview/Pbx.GetQueuePerformanceOverviewData(periodFrom={periodFrom},periodTo={periodTo},queueDns={queueDns},waitInterval={waitInterval})
#	source: https://github.com/luxzg/3CX-XAPI_examples
#	by Luka Pribanić Lux, 2025-03-17

function Get-ReportQueuePerformanceOverview {
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
		[string]$queuedns = "",						# Example queuedns is extension number eg "1234"
	[string]$waitInterval = "0:00:0",				# Example waitInterval (in seconds)
    [Parameter(Mandatory,
		HelpMessage="Provide number as integer for amount of records to fetch")]
		[int]$top,									# = 100000,
    [Parameter(Mandatory,
		HelpMessage="Provide number as integer for amount of records to skip")]
		[int]$skip									# = 0
)

# Format paths
$paths = Get-ExportPaths -path $ModuleRoot -functionname $MyInvocation.MyCommand -from $from -to $to -top $top -skip $skip

# Check if PowerShell version is <=5.1 or >=7.5, store major version, otherwise fail
$pscheck = Test-PowerShellModuleVersion

# Fetch XAPI token
$token = Get-XAPIToken -url $url -user $user -key $key

# Fix date/time if user provided alternative format without time, with timezone suffix, or similar
$from = Convert-IsoDateTimeToZulu($from)
$to = Convert-IsoDateTimeToZulu($to)

# Define ReportQueuePerformanceOverview URI ; prefered order of parameters: $search $filter $count $orderby $skip $top $expand $select $format
$FullURI = "$url/xapi/v1/ReportQueuePerformanceOverview/Pbx.GetQueuePerformanceOverviewData(periodFrom=$from,periodTo=$to,queueDns='$queuedns',waitInterval='$waitInterval')?`$count=true&`$orderby=QueueDn asc&`$skip=$skip&`$top=$top"

# Fetch data from URI, limit progressbar length to MaxSeconds, two paths depending on PowerShell version 5 or 7
$response = Invoke-XAPIRequestWithProgress -uri $FullURI -token $token -MaxSeconds 180 -Activity "Fetching data from XAPI..." -pscheck $pscheck

# Check response data, count records, warn if something is wrong
Test-Response -data $response

# Add new formatted columns, with progress bar functionality
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "TalkTime" -NewColumn "TalkTime (text)" -Formatter { param($colValue) Convert-IsoDurationToHumanReadable $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "TalkTime" -NewColumn "TalkTime (seconds)" -Formatter { param($colValue) Convert-IsoDurationToSeconds $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "TalkTime" -NewColumn "TalkTime (hh:mm:ss)" -Formatter { param($colValue) Convert-IsoDurationToSecondsToExcelTimeValue $colValue }

Complete-ProgressBar -Activity "Processing records"

# Show sample data, using columns for select
$columns = @('ExtensionDisplayName', 'ExtensionDn', 'QueueDisplayName', 'TalkTime', 'TalkTime (text)', 'TalkTime (seconds)', 'TalkTime (hh:mm:ss)')
Show-Sample -data $response -columns $columns

# Export results to CSV & XLSX (with rename/overwrite prompt if file exists)
$csvFinalPath = Export-DataToCSV -data $response.value -csvPath $paths.CsvPath
$excelFinalPath = Export-DataToExcel -data $response.value -excelPath $paths.ExcelPath -ColumnFormats @{ "TalkTime (seconds)"  = '0'; "TalkTime (hh:mm:ss)" = '[h]:mm:ss;@' }

# Test if export of CSV and/or Excel was completed, and inform user
Test-ExportResults -csv $csvFinalPath -excel $excelFinalPath

}
# Export function for use in the module
Export-ModuleMember -Function Get-ReportQueuePerformanceOverview
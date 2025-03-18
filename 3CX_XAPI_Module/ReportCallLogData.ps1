# ReportCallLogData.ps1
# swagger specs : /ReportCallLogData/Pbx.GetCallLogData(periodFrom={periodFrom},periodTo={periodTo},sourceType={sourceType},sourceFilter={sourceFilter},destinationType={destinationType},destinationFilter={destinationFilter},callsType={callsType},callTimeFilterType={callTimeFilterType},callTimeFilterFrom={callTimeFilterFrom},callTimeFilterTo={callTimeFilterTo},hidePcalls={hidePcalls})
#	source: https://github.com/luxzg/3CX-XAPI_examples
#	by Luka Pribanić Lux, 2025-03-17

function Get-ReportCallLogData {
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
    [int]$sourceType = 0,							# Example sourceType
    [string]$sourceFilter = "",						# Example sourceFilter
    [int]$destinationType = 0,						# Example destinationType
    [string]$destinationFilter = "",				# Example destinationFilter
    [int]$callsType = 0,							# Example callsType
    [int]$callTimeFilterType = 0,					# Example callTimeFilterType
    [string]$callTimeFilterFrom = '0:00:0',			# Example callTimeFilterFrom
    [string]$callTimeFilterTo = '0:00:0',			# Example callTimeFilterTo
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

# Define ReportCallLogData URI ; prefered order of parameters: $search $filter $count $orderby $skip $top $expand $select $format
$FullURI = "$url/xapi/v1/ReportCallLogData/Pbx.GetCallLogData(periodFrom=$from,periodTo=$to,sourceType=$sourceType,sourceFilter='$sourceFilter',destinationType=$destinationType,destinationFilter='$destinationFilter',callsType=$callsType,callTimeFilterType=$callTimeFilterType,callTimeFilterFrom='$callTimeFilterFrom',callTimeFilterTo='$callTimeFilterTo',hidePcalls=false)?`$count=true&`$orderby=StartTime asc&`$skip=$skip&`$top=$top"

# Fetch data from URI, limit progressbar length to MaxSeconds, two paths depending on PowerShell version 5 or 7
$response = Invoke-XAPIRequestWithProgress -uri $FullURI -token $token -MaxSeconds 180 -Activity "Fetching data from XAPI..." -pscheck $pscheck

# Check response data, count records, warn if something is wrong
Test-Response -data $response

# Add new formatted columns, with progress bar functionality
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "TalkingDuration" -NewColumn "TalkingDuration (text)" -Formatter { param($colValue) Convert-IsoDurationToHumanReadable $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "TalkingDuration" -NewColumn "TalkingDuration (seconds)" -Formatter { param($colValue) Convert-IsoDurationToSeconds $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "TalkingDuration" -NewColumn "TalkingDuration (hh:mm:ss)" -Formatter { param($colValue) Convert-IsoDurationToSecondsToExcelTimeValue $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "RingingDuration" -NewColumn "RingingDuration (text)" -Formatter { param($colValue) Convert-IsoDurationToHumanReadable $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "RingingDuration" -NewColumn "RingingDuration (seconds)" -Formatter { param($colValue) Convert-IsoDurationToSeconds $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "RingingDuration" -NewColumn "RingingDuration (hh:mm:ss)" -Formatter { param($colValue) Convert-IsoDurationToSecondsToExcelTimeValue $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "StartTime" -NewColumn "StartLocalDate" -Formatter { param($colValue) Convert-IsoDateTimeToLocalDate $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "StartTime" -NewColumn "StartLocalTime" -Formatter { param($colValue) Convert-IsoDateTimeToLocalTime $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "StartTime" -NewColumn "DayOfWeek" -Formatter { param($colValue) Convert-IsoDateTimeToDayOfWeek $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "StartTime" -NewColumn "DayOfWeekCroatian" -Formatter { param($colValue) Convert-IsoDateTimeToDayOfWeekCro $colValue }

Complete-ProgressBar -Activity "Processing records"

# Show sample data, using columns for select
$columns = @('StartTime', 'SourceDisplayName', 'DestinationDisplayName', 'TalkingDuration (text)', 'TalkingDuration (seconds)', 'TalkingDuration (hh:mm:ss)', 'RingingDuration (text)', 'RingingDuration (seconds)', 'RingingDuration (hh:mm:ss)', 'StartLocalDate', 'StartLocalTime', 'DayOfWeek', 'DayOfWeekCroatian')
Show-Sample -data $response -columns $columns

# Export results to CSV & XLSX (with rename/overwrite prompt if file exists)
$csvFinalPath = Export-DataToCSV -data $response.value -csvPath $paths.CsvPath
$excelFinalPath = Export-DataToExcel -data $response.value -excelPath $paths.ExcelPath -ColumnFormats @{ "TalkingDuration (seconds)"  = '0'; "TalkingDuration (hh:mm:ss)" = 'hh:mm:ss'; "RingingDuration (seconds)"  = '0'; "RingingDuration (hh:mm:ss)" = 'hh:mm:ss' ; 'StartLocalDate' = 'yyyy-mm-dd' }

# Test if export of CSV and/or Excel was completed, and inform user
Test-ExportResults -csv $csvFinalPath -excel $excelFinalPath

}
# Export function for use in the module
Export-ModuleMember -Function Get-ReportCallLogData
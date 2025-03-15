# CallHistoryView.ps1

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
		HelpMessage="Provide date/time format: YYYY-MM-DD")]
		[string]$from,								# = "2024-12-01",
    [Parameter(Mandatory,
		HelpMessage="Provide date/time format: YYYY-MM-DD")]
		[string]$to,								# = "2024-12-31",
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
    $($paths.ScriptDir)\$($paths.ScriptName) -user "test" -key "your_client_secret" -url "https://YourSubdomainHere.3cx.eu:5001" -from "YYYY-MM-DD" -to "YYYY-MM-DD" -top 100000 -skip 0

EXAMPLES:
    $($paths.ScriptDir)\$($paths.ScriptName) -user "test" -key "abc123" -url "https://example.3cx.eu:5001" -from "2025-02-01" -to "2025-02-28" -top 50000 -skip 1000
    $($paths.ScriptDir)\$($paths.ScriptName) -user "admin" -key "xyz456" -url "https://yourpbx.3cx.eu:5001" -from "2024-12-01" -to "2024-12-31" -top 200000 -skip 0
"@
Show-HelpNotes
    exit 0
}

# Run only on PowerShell 5.x until I can fix date/time formatting for PS 7.x
Confirm-PowerShellModuleVersion -MinMajorVersion 5

# Fetch XAPI token
$token = Get-XAPIToken -url $url -user $user -key $key

# Define CallHistoryView URI ; prefered order of parameters: $search $filter $count $orderby $skip $top $expand $select $format
$FullURI = "$url/xapi/v1/CallHistoryView?`$filter=date(SegmentStartTime) ge $from and date(SegmentStartTime) le $to&`$count=true&`$orderby=SegmentStartTime asc&`$skip=$skip&`$top=$top"

# Fetch data from URI, limit progressbar length to MaxSeconds
$response = Invoke-XAPIRequestWithProgress -uri $FullURI -token $token -MaxSeconds 180 -Activity "Fetching data from XAPI..."

# Check response data, count records, warn if something is wrong
Test-Response -data $response

# Add new formatted columns, with progress bar functionality
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "CallTime" -NewColumn "CallTime (text)" -Formatter { param($colValue) Convert-IsoDurationToHumanReadable $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "CallTime" -NewColumn "CallTime (seconds)" -Formatter { param($colValue) Convert-IsoDurationToSeconds $colValue }
$response.value = Add-FormattedColumn -data $response.value -OriginalColumn "CallTime" -NewColumn "CallTime (hh:mm:ss)" -Formatter { param($colValue) Convert-IsoDurationToSecondsToExcelTimeValue $colValue }

Complete-ProgressBar -Activity "Processing records"

# Show sample data, using columns for select
$columns = @('SegmentStartTime', 'SegmentEndTime', 'SrcExtendedDisplayName', 'DstExtendedDisplayName', 'CallTime (text)', 'CallTime (seconds)', 'CallTime (hh:mm:ss)')
Show-Sample -data $response -columns $columns

# Export results to CSV & XLSX (with rename/overwrite prompt if file exists)
$csvFinalPath = Export-DataToCSV -data $response.value -csvPath $paths.CsvPath
$excelFinalPath = Export-DataToExcel -data $response.value -excelPath $paths.ExcelPath -ColumnFormats @{ "CallTime (seconds)"  = '0'; "CallTime (hh:mm:ss)" = 'hh:mm:ss' }

# Test if export of CSV and/or Excel was completed, and inform user
Test-ExportResults -csv $csvFinalPath -excel $excelFinalPath

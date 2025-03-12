# Luka Pribanić Lux, 2025-03-12

# Set default parameters
param(
    [string]$user = "test",
    [string]$key,
    [string]$url = "https://YourSubdomainHere.3cx.eu:5001",
    [string]$from = "2025-02-01",
    [string]$to = "2025-02-28",
    [int]$top = 100000,
    [switch]$help
)

# Get script directory to save files in the same location
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Show help if invoked
if ($help) {
	Write-Host ""
    Write-Host @"
USAGE:
    $scriptDir\fetch_call_history.ps1 -user "test" -key "your_client_secret" -url "https://YourSubdomainHere.3cx.eu:5001" -from "YYYY-MM-DD" -to "YYYY-MM-DD" -top 100000

EXAMPLES:
    $scriptDir\fetch_call_history.ps1 -user "test" -key "abc123" -url "https://example.3cx.eu:5001" -from "2025-02-01" -to "2025-02-28" -top 50000
    $scriptDir\fetch_call_history.ps1 -user "admin" -key "xyz456" -url "https://yourpbx.3cx.eu:5001" -from "2024-12-01" -to "2024-12-31" -top 200000

NOTES:
- Replace 'your_client_secret' with a valid API key, '-key' parameter is required.
- Date range will include both the starting and the ending date (-from and -to values).
- "ImportExcel" module is required for XLSX export: https://github.com/dfinke/ImportExcel
- Ensure that the ImportExcel module is installed and imported in your PowerShell session. You can install it using the following command:
	Install-Module -Name ImportExcel -Scope CurrentUser
- After installing, import the module:
	Import-Module ImportExcel
- In case that ImportExcel module is not available, XLSX export will be skipped.
- The '-top' parameter limits the number of records fetched.
- Running command with default parameters will use:
	-user "test" -url "https://YourSubdomainHere.3cx.eu:5001" -from "2025-02-01" -to "2025-02-28" -top 100000

"@
    exit 0
}

# Check if key was provided
if (-not $key) {
    Write-Host "Error: Please provide the API key using '-key' parameter. To see complete help use '-help'."
    exit 1
}

# Time the script
Write-Host "`nScript started: " $(date)

# Reset global variables to avoid issues from previous runs
$global:response = @()
$global:callhistory = @()

# Set path to save files in the same directory location as the script
$csvPath = "$scriptDir\CallHistoryView-$from-to-$to.csv"
$xlsxPath = "$scriptDir\CallHistoryView-$from-to-$to.xlsx"

# Request Bearer Token
try {
    $tokenResponse = Invoke-WebRequest -Uri "$url/connect/token" -Method POST -Body @{
        client_id=$user
        client_secret=$key
        grant_type='client_credentials'
    } | ConvertFrom-Json
} catch {
    Write-Host "Error obtaining token: $_" -ForegroundColor Red
    exit 1
}

$global:token = $tokenResponse.access_token

$headers = @{ Authorization = "Bearer $($tokenResponse.access_token)" }

# Fetch call history URI
$FullURI = "$url/xapi/v1/CallHistoryView?`$orderby=SegmentStartTime asc&`$top=$top&`$filter=date(SegmentStartTime) ge $from and date(SegmentStartTime) le $to&`$count=true"

# Function to convert ISO 8601 CallTime to Excel-friendly format
function Convert-CallTime($isoDuration) {
    if ($isoDuration -match '^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$') {
        $hours = if ($matches[1]) { [int]$matches[1] } else { 0 }
        $minutes = if ($matches[2]) { [int]$matches[2] } else { 0 }
        $seconds = if ($matches[3]) { [math]::Round([decimal]$matches[3]) } else { 0 }

        # Ensure seconds/minutes overflow is handled correctly
        if ($seconds -ge 60) {
            $minutes += [math]::Floor($seconds / 60)
            $seconds = $seconds % 60
        }
        if ($minutes -ge 60) {
            $hours += [math]::Floor($minutes / 60)
            $minutes = $minutes % 60
        }

        # Ensure all values are properly converted to integers
        $hours = [int]$hours
        $minutes = [int]$minutes
        $seconds = [int]$seconds

        # Format as HH:MM:SS
        return "{0:D2}:{1:D2}:{2:D2}" -f $hours, $minutes, $seconds
    }
    return "00:00:00"
}

# Function to convert ISO 8601 CallTime to total seconds
function Convert-CallTimeToSeconds($isoDuration) {
    if ($isoDuration -match '^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$') {
        $hours = if ($matches[1]) { [int]$matches[1] } else { 0 }
        $minutes = if ($matches[2]) { [int]$matches[2] } else { 0 }
        $seconds = if ($matches[3]) { [math]::Round([decimal]$matches[3]) } else { 0 }
        return ($hours * 3600) + ($minutes * 60) + [math]::Round($seconds)  # Return total seconds
    }
    return 0
}

Write-Host "`nCalling XAPI using this URI:"
Write-Host "Invoke-RestMethod -Method Get -Uri $FullURI -Headers $headers"

# Inform user that API request can take time
Write-Host ""
Write-Host "Fetching call history, this may take some time, please wait..." -ForegroundColor Yellow

# Make the API call directly and store the result
$global:response = Invoke-RestMethod -Method Get -Uri $FullURI -Headers $headers
$global:callhistory = $global:response | Select-Object -ExpandProperty value # Extracts call history data value
Write-Host "Done fetching call history!"
Write-Host "Total rows in filtered query:" $global:response.'@odata.count'
Write-Host "Total rows fetched: $($global:callhistory.Count)`n"

# Add formatted columns with progress bar
Write-Host "Please wait while adding formatted columns for 'CallTime (seconds)' & 'CallTime (formatted)' (...outputingo every 1000th row as preview...)"

$maxItems = $global:callhistory.Count  # Total number of items to process
$progressStep = 100 / $maxItems  # Step size for progress bar
$batchSize = 1000  # Update progress every 1000 items

$global:callhistory = $global:callhistory | ForEach-Object -Begin {
    $i = 0  # Initialize item counter
    $batchCounter = 0  # Initialize batch counter
} -Process {
    $i++
    $batchCounter++

    # Add both columns in a single pipeline
    $_ | Add-Member -NotePropertyName "CallTime (formatted)" -NotePropertyValue (Convert-CallTime $_.CallTime) -PassThru | 
		 Add-Member -NotePropertyName "CallTime (seconds)" -NotePropertyValue (Convert-CallTimeToSeconds $_.CallTime) -PassThru

    # Update progress every 1000 items
    if ($batchCounter -ge $batchSize) {
        Write-Progress -Status "Adding columns" -Activity "Processing item $i of $maxItems" -PercentComplete (($i / $maxItems) * 100)
        $batchCounter = 0  # Reset batch counter
		
		# Output the last record as preview of the running batch
		if ($i -eq $batchSize) {
			Write-Host "SegmentStartTime `t SegmentEndTime `t SrcExtendedDisplayName `t DstExtendedDisplayName `t 'CallTime (seconds)'"
			Write-Host "$($_.SegmentStartTime) `t $($_.SegmentEndTime) `t $($_.SrcExtendedDisplayName) `t $($_.DstExtendedDisplayName) `t $($_.'CallTime (seconds)')"
		} else {
			Write-Host "$($_.SegmentStartTime) `t $($_.SegmentEndTime) `t $($_.SrcExtendedDisplayName) `t $($_.DstExtendedDisplayName) `t $($_.'CallTime (seconds)')"
		}
    }

} -End {
    Write-Progress -Status "Completed" -Activity "All records processed" -PercentComplete 100
    Start-Sleep -Seconds 1  # Optional: Small delay to display 100% before closing
    Write-Progress -Completed -Activity "All records processed" # Close the progress bar
}

Write-Host "Added formatted columns for 'CallTime (seconds)' & 'CallTime (formatted)' !`n"

# Display first & last 10 records
Write-Host "Output sample for first and last 10 rows, selected columns only: "
$global:callhistory | Select-Object -First 10 | Select SegmentStartTime, SegmentEndTime, SrcExtendedDisplayName, DstExtendedDisplayName, 'CallTime (seconds)' | Format-Table -AutoSize
$global:callhistory | Select-Object -Last 10 | Select SegmentStartTime, SegmentEndTime, SrcExtendedDisplayName, DstExtendedDisplayName, 'CallTime (seconds)' | Format-Table -AutoSize
Write-Host "Output sample for first record, formatted as list:"
$global:callhistory | Select-Object -First 1 | Format-List

# Check if files exist and prompt user
$csvExists = Test-Path $csvPath
$xlsxExists = Test-Path $xlsxPath

if ($csvExists -or $xlsxExists) {
    $choice = Read-Host "Files $csvPath and/or $xlsxPath already exist. Overwrite (O) or Rename (R)? [O/R]"
    
    if ($choice -eq "O" -or $choice -eq "o") {
        # Overwrite case
        if ($xlsxExists) {
            Remove-Item $xlsxPath -Force  # Ensure Excel file is deleted before new creation
        }
        Write-Host "Overwriting existing files..."
    } else {
        # Rename files with timestamp
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $csvPath = "$scriptDir\CallHistoryView-$from-to-$to-$timestamp.csv"
        $xlsxPath = "$scriptDir\CallHistoryView-$from-to-$to-$timestamp.xlsx"
        Write-Host "Renaming output to: $csvPath and $xlsxPath"
    }
	
	Write-Host ""
}

# Export CSV
Write-Host "Exporting to CSV format..."
$global:callhistory | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "CSV exported to:"
Write-Host "`t$csvPath`n" -ForegroundColor Cyan

# Export to Excel and apply time format to "CallTime (formatted)" columns if ImportExcel module is available
if (Get-Module -ListAvailable -Name ImportExcel) {
    # Export the data to Excel
	Write-Host "Exporting to Excel format..."
	$global:callhistory | Export-Excel -Path $xlsxPath -WorksheetName 'CallHistory' -AutoSize -CellStyleSB {
		param($workSheet, $totalRows, $lastColumn)

		# Find the "CallTime (seconds)" column index
		$headerRow = 1
		$columnIndex = ($workSheet.Cells["1:1"] | Where-Object { $_.Text -eq "CallTime (seconds)" }).Start.Column

		Write-Host "Excel formatting for time started...!"
		if ($columnIndex) {
			# Convert seconds to Excel time by dividing by 86400 (seconds in a day)
			for ($row = 2; $row -le $totalRows + 1; $row++) {
				$cell = $workSheet.Cells[$row, $columnIndex]
				$cell.Value = $cell.Value / 86400 # Convert to Excel time format
			}
			# Apply time format to the column
			$workSheet.Column($columnIndex).Style.Numberformat.Format = 'hh:mm:ss'
			Write-Host "Excel formatting completed successfully on 'CallTime (seconds)' column!"
		} else {
			Write-Host "WARNING: 'CallTime (seconds)' column not found, unable to format." -ForegroundColor Yellow
		}
	}
    Write-Host "Excel exported to:"
	Write-Host "`t$xlsxPath`n" -ForegroundColor Cyan
} else {
    Write-Host "Excel export skipped (ImportExcel module not found). Install it from:"
    Write-Host "https://github.com/dfinke/ImportExcel"
	Write-Host "To get more information run $scriptDir\fetch_call_history.ps1 -help"
}

Write-Host "Total rows in filtered query: $($global:response.'@odata.count')"
Write-Host "Total rows fetched: $($global:callhistory.Count)"

if ($global:response.'@odata.count' -eq $global:callhistory.Count) {
    Write-Host "`tThe entire dataset has been fetched." -ForegroundColor Green
	} else {
    Write-Host "`tThe dataset has been partially fetched. You may consider increasing the -top parameter." -ForegroundColor Yellow
	}

Write-Host "`nData is still available for manual processing by calling variables:"
Write-Host "`t`$global:token" -ForegroundColor Cyan
Write-Host "`t`$global:response" -ForegroundColor Cyan
Write-Host "`t`$global:callhistory" -ForegroundColor Cyan
Write-Host "Examples:"
Write-Host "`t`$global:response.'@odata.context'" -ForegroundColor Cyan
Write-Host "`t`$global:response.'@odata.count'" -ForegroundColor Cyan
Write-Host "`t`$global:callhistory.Count" -ForegroundColor Cyan
Write-Host "`t`$global:callhistory | Select-Object -First 3 | ft" -ForegroundColor Cyan
Write-Host "`t`$global:callhistory | Select-Object -Last 1 | fl" -ForegroundColor Cyan

Write-Host "`nScript finished: " $(date)
Write-Host ""

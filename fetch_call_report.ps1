# Luka Pribanić Lux, 2025-03-12

# Set default parameters
param(
    [string]$user = "test",
    [string]$key,
    [string]$url = "https://YourSubdomainHere.3cx.eu:5001",
    [string]$from = "2024-12-01T00:00:00Z",			# Use ISO 8601 Zulu time format
    [string]$to = "2024-12-31T23:59:59Z",			# Use ISO 8601 Zulu time format
    [int]$sourceType = 0,							# Example sourceType
    [string]$sourceFilter = "",						# Example sourceFilter
    [int]$destinationType = 0,						# Example destinationType
    [string]$destinationFilter = "",				# Example destinationFilter
    [int]$callsType = 0,							# Example callsType
    [int]$callTimeFilterType = 0,					# Example callTimeFilterType
    [string]$callTimeFilterFrom = '0:00:0',			# Example callTimeFilterFrom
    [string]$callTimeFilterTo = '0:00:0',			# Example callTimeFilterTo
    [int]$top = 100000,								# Example top parameter
    [int]$skip = 0,									# Example skip parameter
    [string]$search = "",							# Example search filter
    [string]$filter = "",							# Example filter
    [switch]$help
)

# Get script directory to save files in the same location
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Show help if invoked
if ($help) {
	Write-Host ""
    Write-Host @"
USAGE:
    $scriptDir\fetch_call_report.ps1 -user "test" -key "your_client_secret" -url "https://YourSubdomainHere.3cx.eu:5001" -from "YYYY-MM-DDTHH:MM:SSZ" -to "YYYY-MM-DDTHH:MM:SSZ" -top 100000

EXAMPLES:
    $scriptDir\fetch_call_report.ps1 -user "test" -key "abc123" -url "https://example.3cx.eu:5001" -from "2025-02-01T00:00:00Z" -to "2025-02-28T23:59:59Z" -top 50000
	$scriptDir\fetch_call_report.ps1 -user "admin" -key "xyz456" -url "https://yourpbx.3cx.eu:5001" -from "2024-12-01T00:00:00-01:00" -to "2024-12-31T23:59:59-01:00" -top 200000

NOTES:
- Replace 'your_client_secret' with a valid API key, '-key' parameter is required.
- The '-from' and '-to' parameters should be in the "YYYY-MM-DDTHH:MM:SS" format.
- Date range will include both the starting and the ending date (-from and -to values).
- "ImportExcel" module is required for XLSX export: https://github.com/dfinke/ImportExcel
- Ensure that the ImportExcel module is installed and imported in your PowerShell session. You can install it using the following command:
	Install-Module -Name ImportExcel -Scope CurrentUser
- After installing, import the module:
	Import-Module ImportExcel
- In case that ImportExcel module is not available, XLSX export will be skipped.
- The '-top' parameter limits the number of records fetched.
- The '-skip' parameter allows skipping records for pagination.
- Running command with default parameters will use:
  -user "$user" -url "$url" -from "$from" -to "$to" -top $top

"@
    exit 0
}

# Check if key was provided
if (-not $key) {
    Write-Host "Error: Please provide the API key using '-key' parameter. To see complete help use '-help'."
    exit 1
}

# Run only on PowerShell 5.x until I can fix date/time formatting for PS 7.x
if ($PSVersionTable.PSVersion.Major -gt 5) {
    Write-Host "Warning: Script requires PowerShell version 5.1 or lower." -ForegroundColor Red
    exit
}

$ErrorActionPreference = "Stop"

# Time the script
Write-Host "`nScript started: " $(date)

# Reset global variables to avoid issues from previous runs
$global:response = @()
$global:callhistory = @()

# Set path to save files in the same directory location as the script
# Replace colon with hyphen in $from and $to for valid file path
$from2 = $from -replace ":", "-"
$to2 = $to -replace ":", "-"
$csvPath = "$scriptDir\ReportCallLogData-$from2-to-$to2.csv"
$xlsxPath = "$scriptDir\ReportCallLogData-$from2-to-$to2.xlsx"

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

$headers = @{ Authorization = "Bearer $($global:token)" }

# Define the full URI with query parameters using parameters (modified for new endpoint)
$FullURI = "$url/xapi/v1/ReportCallLogData/Pbx.GetCallLogData(periodFrom=$from,periodTo=$to,sourceType=$sourceType,sourceFilter='$sourceFilter',destinationType=$destinationType,destinationFilter='$destinationFilter',callsType=$callsType,callTimeFilterType=$callTimeFilterType,callTimeFilterFrom='$callTimeFilterFrom',callTimeFilterTo='$callTimeFilterTo',hidePcalls=true)?`$orderby=StartTime asc&`$top=$top&`$skip=$skip&`$count=true"

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

function ConvertStartTime($startTime) {
    try {
        # Define day names in English and Croatian
        $dayNamesEnglish = @('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')
		$dayNamesCroatian = @('nedjelja', 'ponedjeljak', 'utorak', 'srijeda', 'cetvrtak', 'petak', 'subota')

        # Remove fractions of a second (if present) and keep the 'Z' at the end
        $startTime = $startTime -replace '\.\d+Z$', 'Z'  # Remove fractions of a second and preserve 'Z'

        # Parse the datetime and convert to local time (CET)
        $dateTime = [datetime]::ParseExact($startTime, 'yyyy-MM-ddTHH:mm:ssZ', $null).ToLocalTime()

        # Format to Date (YYYY-MM-DD)
        $dateFormatted = $dateTime.ToString('yyyy-MM-dd')

        # Format to Time (HH:mm:ss)
        $timeFormatted = $dateTime.ToString('HH:mm:ss')

        # Get Day of the Week (English)
        $dayOfWeekEnglish = $dayNamesEnglish[$dateTime.DayOfWeek]

        # Get Day of the Week (Croatian)
        $dayOfWeekCroatian = $dayNamesCroatian[$dateTime.DayOfWeek]

        # Return all the values as an object (or output the desired ones)
        return @{
            Date           = $dateFormatted
            Time           = $timeFormatted
            DayOfWeek      = $dayOfWeekEnglish
            DayOfWeekCro   = $dayOfWeekCroatian
        }
    }
    catch {
        Write-Warning "Invalid StartTime format for $startTime. Skipping conversion."
        return $null
    }
}

function Convert-ToZuluTime {
    param (
        [string]$inputDateTime
    )
    
    # Try parsing the input date-time
    try {
        # Parse the input date-time string
        $dateTime = [datetime]::Parse($inputDateTime)
        
        # Convert to UTC and then format to ISO 8601 Zulu time (ending with Z)
        $zuluTime = $dateTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        
        return $zuluTime
    }
    catch {
        Write-Host "Invalid date-time format provided. Please provide a valid ISO 8601 date-time." -ForegroundColor Red
        exit 1
    }
}

$from = Convert-ToZuluTime($from)
$to = Convert-ToZuluTime($to)

Write-Host "`nCalling XAPI using this URI:"
Write-Host "Invoke-RestMethod -Method Get -Uri $FullURI -Headers $headers"

# Inform user that API request can take time
Write-Host ""
Write-Host "Fetching call history, this may take some time, please wait..." -ForegroundColor Yellow

# Start a background job to fetch the data
$job = Start-Job -ScriptBlock {
    param($FullURI, $headers)

    try {
        $response = Invoke-RestMethod -Method Get -Uri $FullURI -Headers $headers
        return $response  # Return the entire response
    }
    catch {
        Write-Host "Error occurred while fetching the data. The request might have timed out or encountered an issue."
        Write-Host "Error details: $($_.Exception.Message)"
        exit 1  # Exit with error code to indicate failure
    }
} -ArgumentList $FullURI, $headers

# Display a progress bar while waiting for the job to complete
$progress = 0
$maxProgress = 100  # Progress bar max value
$maxTime = 180      # 3 minutes (180 seconds)
$startTime = Get-Date

while ($job.State -eq "Running") {
	$elapsedTime = (Get-Date) - $startTime
	# Calculate rounded progress and format as "5.0%" instead of "5%"
    $progress = [math]::Min(($elapsedTime.TotalSeconds / $maxTime) * $maxProgress, $maxProgress)
	
	# Display the progress bar
	Write-Progress -PercentComplete $progress -Activity "Fetching call history..." -Status "$([math]::Round($progress, 1))% Complete"

	# Sleep for 1s and increase progress
    Start-Sleep -Seconds 1
}

# Ensure progress reaches 100% when the task completes
Write-Progress -Completed -Activity "All records processed"  # Close the progress bar

# Retrieve results once the job is complete
Write-Host "`nProcessing received data..."

$global:response = Receive-Job -Job $job
Remove-Job -Job $job

$global:callhistory = $global:response | Select-Object -ExpandProperty value | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName # Extracts call history data value and exclude the job metadata

Write-Host "Done fetching call history!"
Write-Host "Total rows in filtered query:" $global:response.'@odata.count'
Write-Host "Total rows fetched: $($global:callhistory.Count)`n"

if ($global:response.'@odata.count' -eq 0) {
	Write-Host "No data matching this filter!`n" -ForegroundColor Red
	exit 1
	}

# Add formatted columns with progress bar
Write-Host "Please wait while adding formatted columns for 'TalkingDuration', 'RingingDuration', 'StartDate', 'DayOfWeek', ... (...outputingo every 1000th row as preview...)"

$maxItems = $global:callhistory.Count  # Total number of items to process
$progressStep = 100 / $maxItems  # Step size for progress bar
$batchSize = 1000  # Update progress every 1000 items

$global:callhistory = $global:callhistory | ForEach-Object -Begin {
    $i = 0  # Initialize item counter
    $batchCounter = 0  # Initialize batch counter
} -Process {
    $i++
    $batchCounter++

	# Call ConvertStartTime function and get the values for each record
    $convertedStartTime = ConvertStartTime $_.StartTime

    # Add both columns in a single pipeline
    $_ | Add-Member -NotePropertyName "TalkingDuration (formatted)" -NotePropertyValue (Convert-CallTime $_.TalkingDuration) -PassThru |
         Add-Member -NotePropertyName "RingingDuration (formatted)" -NotePropertyValue (Convert-CallTime $_.RingingDuration) -PassThru |
         Add-Member -NotePropertyName "TalkingDuration (seconds)" -NotePropertyValue (Convert-CallTimeToSeconds $_.TalkingDuration) -PassThru |
         Add-Member -NotePropertyName "RingingDuration (seconds)" -NotePropertyValue (Convert-CallTimeToSeconds $_.RingingDuration) -PassThru | 
		 Add-Member -NotePropertyName "StartDate" -NotePropertyValue $convertedStartTime.Date -PassThru |
		 Add-Member -NotePropertyName "StartTimeLocal" -NotePropertyValue $convertedStartTime.Time -PassThru |
		 Add-Member -NotePropertyName "DayOfWeek" -NotePropertyValue $convertedStartTime.DayOfWeek -PassThru |
		 Add-Member -NotePropertyName "DayOfWeekCroatian" -NotePropertyValue $convertedStartTime.DayOfWeekCro -PassThru

    # Update progress every 1000 items
    if ($batchCounter -ge $batchSize) {
        Write-Progress -Status "Adding columns" -Activity "Processing item $i of $maxItems" -PercentComplete (($i / $maxItems) * 100)
        $batchCounter = 0  # Reset batch counter
		
		# Output the last record as preview of the running batch
		if ($i -eq $batchSize) {
			Write-Host "StartTime `t SourceDisplayName `t DestinationDisplayName `t RingingDuration (formatted) `t TalkingDuration (formatted) `t DayOfWeek"
			Write-Host "$($_.StartTime) `t $($_.SourceDisplayName) `t $($_.DestinationDisplayName) `t $($_.'RingingDuration (formatted)') `t $($_.'TalkingDuration (formatted)') `t $($_.DayOfWeek)"
		} else {
			Write-Host "$($_.StartTime) `t $($_.SourceDisplayName) `t $($_.DestinationDisplayName) `t $($_.'RingingDuration (formatted)') `t $($_.'TalkingDuration (formatted)') `t $($_.DayOfWeek)"
		}
    }

} -End {
    Write-Progress -Status "Completed" -Activity "All records processed" -PercentComplete 100
    Start-Sleep -Seconds 1  # Optional: Small delay to display 100% before closing
    Write-Progress -Completed -Activity "All records processed" # Close the progress bar
}

Write-Host "Added formatted columns for 'TalkingDuration', 'RingingDuration', 'StartDate', 'DayOfWeek' !`n"

# Display first & last 10 records
Write-Host "Output sample for first and last 10 rows, selected columns only: "
$global:callhistory | Select-Object -First 10 | Select StartTime, SourceDisplayName, DestinationDisplayName, 'RingingDuration (formatted)', 'TalkingDuration (formatted)', StartDate, StartTimeLocal, DayOfWeek | Format-Table -AutoSize
$global:callhistory | Select-Object -Last 10 | Select StartTime, SourceDisplayName, DestinationDisplayName, 'RingingDuration (formatted)', 'TalkingDuration (formatted)', StartDate, StartTimeLocal, DayOfWeek | Format-Table -AutoSize
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
        $csvPath = "$scriptDir\ReportCallLogData-$from2-to-$to2-$timestamp.csv"
        $xlsxPath = "$scriptDir\ReportCallLogData-$from2-to-$to2-$timestamp.xlsx"
        Write-Host "Renaming output to: $csvPath and $xlsxPath"
    }
	
	Write-Host ""
}

# Export CSV
Write-Host "Exporting to CSV format..."
$global:callhistory | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "CSV exported to:"
Write-Host "`t$csvPath`n" -ForegroundColor Cyan											   

# Export to Excel and apply time format to "TalkingDuration (seconds)" & "RingingDuration (seconds)" columns if ImportExcel module is available
if (Get-Module -ListAvailable -Name ImportExcel) {
    # Export the data to Excel
	Write-Host "Exporting to Excel format..."
    $global:callhistory | Export-Excel -Path $xlsxPath -WorksheetName 'ReportCallLog' -AutoSize -CellStyleSB {
        param($workSheet, $totalRows, $lastColumn)
		
        # Find the "TalkingDuration (seconds)" & "RingingDuration (seconds)" columns index
		$headerRow = 1
        $columnIndex = ($workSheet.Cells["1:1"] | Where-Object { $_.Text -eq "TalkingDuration (seconds)" }).Start.Column
        $columnIndex2 = ($workSheet.Cells["1:1"] | Where-Object { $_.Text -eq "RingingDuration (seconds)" }).Start.Column

		Write-Host "Excel formatting for time started...!"
        if ($columnIndex) {
			# Convert seconds to Excel time by dividing by 86400 (seconds in a day)
            for ($row = 2; $row -le $totalRows + 1; $row++) {
                $cell = $workSheet.Cells[$row, $columnIndex]
				$cell.Value = $cell.Value / 86400 # Convert to Excel time format
            }
			# Apply time format to the column
            $workSheet.Column($columnIndex).Style.Numberformat.Format = 'hh:mm:ss'
			Write-Host "Excel formatting completed successfully on 'TalkingDuration (seconds)' column!"
		} else {
			Write-Host "WARNING: 'TalkingDuration (seconds)' column not found, unable to format." -ForegroundColor Yellow
		}
        if ($columnIndex2) {
            # Convert seconds to Excel time by dividing by 86400 (seconds in a day)
            for ($row = 2; $row -le $totalRows + 1; $row++) {
                $cell = $workSheet.Cells[$row, $columnIndex2]
                $cell.Value = $cell.Value / 86400 # Convert to Excel time format
            }
			# Apply time format to the column
            $workSheet.Column($columnIndex2).Style.Numberformat.Format = 'hh:mm:ss'
			Write-Host "Excel formatting completed successfully on 'RingingDuration (seconds)' column!"
		} else {
			Write-Host "WARNING: 'RingingDuration (seconds)' column not found, unable to format." -ForegroundColor Yellow
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

# CommonFunctions.psm1

# Getting paths of script and using it for other paths
function Get-ScriptPaths {
    param (
        [Parameter(Mandatory)]$MyInvocation,
        [Parameter(Mandatory)][string]$from,
        [Parameter(Mandatory)][string]$to,
        [Parameter(Mandatory)][int]$top,
        [Parameter(Mandatory)][int]$skip
    )

    # Get script directory ; to save files in correct location
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    # Get script name ; to be able to show in help if script is renamed and for export paths
    $scriptName = $MyInvocation.MyCommand.Name
    # Replace colon with hyphen in $from and $to for valid file paths, if they contain eg hh:mm:ss
	$from = $from -replace ":", "-"
	$to = $to -replace ":", "-"
	# Export paths
    $csvPath = "$scriptDir\exports\$scriptName-from_$($from)_to_$($to)_top_$($top)_skip_$($skip).csv"
    $excelPath = "$scriptDir\exports\$scriptName-from_$($from)_to_$($to)_top_$($top)_skip_$($skip).xlsx"
	
    # Return values as a hashtable
    return @{
        ScriptDir = $scriptDir
        ScriptName = $scriptName
        CsvPath = $csvPath
        ExcelPath = $excelPath
    }
}

# Show geeneral script help notes
function Show-HelpNotes {
    Write-Host @"

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
- The '-skip' parameter allows skipping records for pagination.

"@}

# Obtain authentication token from XAPI
function Get-XAPIToken {
    param (
        [string]$url,
        [string]$user,
        [string]$key
    )

	# Request Bearer Token
	try {
		$tokenUri = "$url/connect/token"
		$tokenResponse = Invoke-RestMethod -Method POST -Uri $tokenUri -Body (@{
			client_id=$user
			client_secret=$key
			grant_type='client_credentials'
		})
	} catch {
		Write-Host "Error obtaining token: $_" -ForegroundColor Red
		exit 1
	}

    return $tokenResponse.access_token
}

function Invoke-XAPIRequestWithProgress {
    param (
        [string]$uri,
        [string]$token,
        [int]$MaxSeconds = 180,
        [string]$Activity = "Fetching Data"
    )

	# Inform user that API request can take time
	Write-Host "`nFetching data from web XAPI, this may take some time, please wait..." -ForegroundColor Yellow
	Write-Host "Calling XAPI using this URI:"
	Write-Host "`t $uri `n" -ForegroundColor Cyan

    $headers = @{ Authorization = "Bearer $token" }

    # Start background / async HTTP request job to fetch the data
    $job = Start-Job -ScriptBlock {
        param($uri, $headers)
		
		try {
			$response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
			return $response  # Return the entire response
		}
		catch {
			Write-Host "Error occurred while fetching the data. The request might have timed out or encountered an issue."
			Write-Host "Error details: $($_.Exception.Message)"
			exit 1  # Exit with error code to indicate failure
		}
    } -ArgumentList $uri, $headers

    # Approximation progress loop
    for ($sec = 1; $sec -le $MaxSeconds; $sec++) {
        if ($job.State -eq 'Completed') {
            break
        }
		# Display the progress bar
        Write-Progress -Activity $Activity -Status "Elapsed $sec sec (~$MaxSeconds sec total)" -PercentComplete (($sec / $MaxSeconds) * 100)
		# Sleep for 1s and increase progress
        Start-Sleep -Seconds 1
    }

    # Wait for the job if it's still running (to finalize)
    $result = Receive-Job -Job $job -Wait -AutoRemoveJob

    Write-Progress -Completed -Activity $Activity
    return $result
}

# Test response data, count records, warn if something is wrong ; to-do : parse returned errors and display in friendly way
function Test-Response {
    param (
        [Parameter(Mandatory)]$data
    )

	$totalFilteredRecords = $data.'@odata.count'
	$totalRecords = $data.value.Count
	Write-Host "Total records filtered: $totalFilteredRecords"
	Write-Host "Total records fetched: $totalRecords"
	
	if ($totalFilteredRecords -eq 0) {
		Write-Host "No data matching this filter!`n" -ForegroundColor Red
		exit 0
	}

	if ($totalRecords -eq 0) {
		Write-Warning "No data returned from API. Exiting script."
		exit 0
	}

	if ($totalFilteredRecords -eq $totalRecords) {
		Write-Host "`tThe entire dataset has been fetched." -ForegroundColor Green
		} else {
		Write-Host "`tThe dataset has been partially fetched. You may consider increasing the -top parameter, or combining -top with -skip for pagination." -ForegroundColor Yellow
		}
}

# Show sample data after fetching and processing data, selected columns only
function Show-Sample {
    param (
        [Parameter(Mandatory)]$data,
        [Parameter(Mandatory)]$columns
    )

	# Display first & last 10 records, with selected columns only
	Write-Host "`nOutput sample for first and last 10 rows, selected columns only: "
	$data.value | Select-Object -First 10 | Select-Object $columns | Format-Table -AutoSize
	$data.value | Select-Object -Last 10  | Select-Object $columns | Format-Table -AutoSize

	Write-Host "Output sample for first record, formatted as list:"
	$data.value | Select-Object -First 1 | Format-List
}

# Export to CSV with fallback handling
function Export-DataToCSV {
    param (
        [Parameter(Mandatory)]$data,
        [Parameter(Mandatory)][string]$csvPath
    )

    if (Test-Path $csvPath) {
		# Check if files exist and prompt user
        Write-Host "File $csvPath already exists."
        $decision = Read-Host "Overwrite, Rename or Cancel? [O/R/C]"
        switch ($decision.ToLower()) {
            'o' { Write-Host "Overwriting existing file." -ForegroundColor Yellow }
            'r' {
                $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
                $csvPath = ($csvPath -replace '\.csv$', "_$timestamp.csv")
                Write-Host "Renamed output to $csvPath" -ForegroundColor Cyan
            }
            default {
                Write-Host "CSV export cancelled. `n" -ForegroundColor Yellow
                return
            }
        }
    }
	
	Write-Host "Starting export to CSV file $csvPath ... `n"
    $data | Export-Csv $csvPath -NoTypeInformation -Encoding utf8
	return $csvPath
}

# Export data to Excel, if ImportExcel module is available
function Export-DataToExcel {
    param (
        [object]$data,
        [string]$excelPath,
        [hashtable]$ColumnFormats  # key: Column name, value: format string, e.g. 'hh:mm:ss'
    )

    if (Test-Path $excelPath) {
		# Check if files exist and prompt user
        Write-Host "File $excelPath already exists."
        $decision = Read-Host "Overwrite, Rename or Cancel? [O/R/C]"
        switch ($decision.ToLower()) {
            'o' {
				Remove-Item $excelPath -Force  # Ensure Excel file is deleted before new creation
				Write-Host "Overwriting existing file." -ForegroundColor Yellow
			}
            'r' {
                $timestamp = Get-Date -Format "yyyyMMddHHmmss"
                $excelPath = ($excelPath -replace '\.xlsx$', "_$timestamp.xlsx")
                Write-Host "Renamed output to $excelPath" -ForegroundColor Cyan
            }
            default {
                Write-Host "Excel export cancelled. `n" -ForegroundColor Yellow
                return
            }
        }
    }

    if (Get-Module -ListAvailable -Name ImportExcel) {
        Import-Module ImportExcel
		# Export to Excel first
        Write-Host "Starting export to Excel file $excelPath ... `n"
		$data | Export-Excel -Path $excelPath -AutoSize -FreezeTopRow -BoldTopRow -AutoFilter
		
		# After export apply column formatting, if specified by user
        if ($ColumnFormats) {
			Write-Host "Excel column formatting specified, processing file... `n"
            $excel = Open-ExcelPackage $excelPath
            $worksheet = $excel.Workbook.Worksheets[1]

            foreach ($columnName in $ColumnFormats.Keys) {
                $colIndex = ($data | Get-Member | Where-Object {$_.Name -eq $columnName}).Count
                if ($columnIndex = ($worksheet.Cells["1:1"] | Where-Object {$_.Value -eq $columnName}).Start.Column) {
                    $worksheet.Column($columnIndex).Style.Numberformat.Format = $ColumnFormats[$columnName]
                }
            }

            Close-ExcelPackage $excel -SaveAs $excelPath
        }
    }
    else {
        Write-Host "ImportExcel module not available, skipping XLSX export. Run with -help to get more information."
		return 0
    }

	return $excelPath
}

# Test if export of CSV and/or Excel was completed
function Test-ExportResults {
    param (
        [string]$csv,
        [string]$excel
    )

	if ($csv -and $excel) {
		Write-Host "Exports completed.`n`tCSV Path:`t $csv`n`tExcel Path:`t $excel" -ForegroundColor Green
	}
	else {
		Write-Host "Export not completed for all files." -ForegroundColor Yellow
	}
}

# Simple progress bar implementation
function Show-ProgressBar {
    param (
        [int]$Current,
        [int]$Total,
        [string]$Activity = "Processing records"
    )

    Write-Progress -Activity $Activity -Status "$Current of $Total processed" -PercentComplete (($Current / $Total) * 100)
}

function Complete-ProgressBar {
    param (
        [string]$Activity
    )

    Write-Progress -Completed -Activity $Activity
}

function Confirm-PowerShellModuleVersion {
    param (
        [int]$MinMajorVersion = 5
    )

    if ($PSVersionTable.PSVersion.Major -gt $MinMajorVersion) {
        Write-Error "Warning: PowerShell version $MinMajorVersion is required. Your version is $($PSVersionTable.PSVersion)."
        exit 1
    }
}

function Add-FormattedColumn {
    param (
        [Parameter(Mandatory)] [array]$data,
        [Parameter(Mandatory)] [string]$OriginalColumn,
        [Parameter(Mandatory)] [string]$NewColumn,
        [Parameter(Mandatory)] [scriptblock]$Formatter,
        [int]$ProgressInterval = 1000,
        [string]$Activity = "Adding formatted column"
    )

	Write-Host "`nPlease wait while formatting column $OriginalColumn to new column $NewColumn)"
    $total = $data.Count
	if ($total -ge $ProgressInterval) {	Write-Host "(... outputing 1 of every $ProgressInterval conversions to console as preview ...)" }
    for ($i = 0; $i -lt $total; $i++) {
        $data[$i] | Add-Member -NotePropertyName $NewColumn -NotePropertyValue (& $Formatter $data[$i].$OriginalColumn)

        if (($i + 1) % $ProgressInterval -eq 0) {
            Show-ProgressBar -Current ($i + 1) -Total $total -Activity "Formatting $NewColumn"
            Write-Host "Last processed record [$($i + 1)] -> preview: $($data[$i].$OriginalColumn) -> $($data[$i].$NewColumn)" -ForegroundColor Cyan
        }
    }

    Complete-ProgressBar -Activity "Formatting $NewColumn"
    return $data
}

Export-ModuleMember -Function *

# CommonFunctions.psm1
# Module containing frequently used functions (except date/time conversions contained in DateTimeFunctions.psm1)
#	source: https://github.com/luxzg/3CX-XAPI_examples
#	by Luka Pribanić Lux, 2025-03-17

# Getting paths of script and using it for other paths
function Get-ExportPaths {
    param (
        [Parameter(Mandatory)][string]$functionname,
        [Parameter(Mandatory)][string]$path,
        [Parameter(Mandatory)][string]$from,
        [Parameter(Mandatory)][string]$to,
        [Parameter(Mandatory)][int]$top,
        [Parameter(Mandatory)][int]$skip
    )

    # Replace colon with hyphen in $from and $to for valid file paths, if they contain eg hh:mm:ss
	$from = $from -replace ":", "-"
	$to = $to -replace ":", "-"
	# Export paths
    $csvPath = "$path\exports\$functionname-from_$($from)_to_$($to)_top_$($top)_skip_$($skip).csv"
    $excelPath = "$path\exports\$functionname-from_$($from)_to_$($to)_top_$($top)_skip_$($skip).xlsx"
	
    # Return values as a hashtable
    return @{
        CsvPath = $csvPath
        ExcelPath = $excelPath
    }
}

# Function to check if PowerShell version is <=5.1 or >=7.5 , otherwise fail
function Test-PowerShellModuleVersion {
    $PSMajorMinor = [System.Version]::new($PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor)

    if ($PSMajorMinor -ge [System.Version]::new(7, 5)) {
        Write-Host "`nPowerShell version is 7.5 or later."
        return 7
    }
    elseif ($PSMajorMinor -le [System.Version]::new(5, 1)) {
        Write-Host "`nPowerShell version is 5.1 or earlier."
        return 5
    }
    else {
		Write-Host "Unsupported PowerShell version detected!"
        Write-Host "- If on an older OS (Windows 7/8.1/Server 2012 R2), use PowerShell 5.1."
        Write-Host "- If on a newer OS, upgrade to PowerShell 7.5.0 or newer for full compatibility."
		Write-Host "- Unfortunately PowerShell 7.4 (LTS) does not support this functionality."
        throw "Current version of PowerShell $($PSVersionTable.PSVersion) is unsupported! `nExiting script."
    }
}

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
		throw "Error obtaining token: $_ `nExiting script."
	}

    return $tokenResponse.access_token
}

function Invoke-XAPIRequestWithProgress {
    param (
        [string]$uri,
        [string]$token,
        [int]$MaxSeconds = 180,
        [string]$Activity = "Fetching Data",
        [int]$pscheck
    )

	# Inform user that API request can take time
	Write-Host "`nFetching data from web XAPI, this may take some time, please wait..." -ForegroundColor Yellow
	Write-Host "Calling XAPI using this URI:"
	Write-Host "`t $uri `n" -ForegroundColor Cyan

    $headers = @{ Authorization = "Bearer $token" }

    # Start background / async HTTP request job to fetch the data
    $job = Start-Job -ScriptBlock {
        param($uri, $headers, $pscheck)
		
		try {
			# use JsonDateKind.String depending on PS version returned by Test-PowerShellModuleVersion
			if($pscheck -eq 5) {
				$response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
			}
			elseif($pscheck -eq 7) {
				# DateKind added to ConvertFrom-Json in PS 7.5
				#	https://github.com/PowerShell/PowerShell/pull/20925/files/d630c18861624724920399aa6a40da7996315786
				$response = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get
				# Force UTF8 encoding
				$response = [Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray() ) | ConvertFrom-Json -DateKind String
			}
			else {
				# Usually shouldn't get here if this is the case!
				throw "PowerShell version not supported! `nExiting script."
			}
			return $response  # Return the entire response
		}
		catch {
			Write-Host "Error occurred while fetching the data. The request might have timed out or encountered an issue."
			throw "Error details: $($_.Exception.Message)"
		}
    } -ArgumentList $uri, $headers, $pscheck

    # Approximation progress loop
    for ($sec = 1; $sec -le $MaxSeconds; $sec++) {
        if ($job.State -ne 'Running') {
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
    if ($result) {
		return $result
	} else {
		throw "No data received from API! `nExiting script."
	}
}

# Test response data, count records, warn/error if something is wrong ; to-do : parse returned errors and display in a more friendly way
function Test-Response {
    param (
        [Parameter(Mandatory)]$data
    )

	$totalFilteredRecords = $data.'@odata.count'
	$totalRecords = $data.value.Count
	Write-Host "Total records filtered: $totalFilteredRecords"
	Write-Host "Total records fetched: $totalRecords"
	
	if ($totalFilteredRecords -eq 0) {
		throw "No data matching this filter! `nExiting script."
	}

	if ($totalRecords -eq 0) {
		throw "No data returned from API! `nExiting script."
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

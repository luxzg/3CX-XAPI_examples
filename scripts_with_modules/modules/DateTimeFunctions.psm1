# DateTimeFunctions.psm1

# Function to convert ISO 8601 time duration to human readable format "HH:mm:ss"
function Convert-IsoDurationToHumanReadable($isoDuration) {
    if ($isoDuration -match '^P(?:(\d+)W)?(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$') {
        $weeks = if ($matches[1]) { [int]$matches[1] } else { 0 }
        $days = if ($matches[2]) { [int]$matches[2] } else { 0 }
        $hours = if ($matches[3]) { [int]$matches[3] } else { 0 }
        $minutes = if ($matches[4]) { [int]$matches[4] } else { 0 }
        $seconds = if ($matches[5]) { [math]::Round([decimal]$matches[5]) } else { 0 }

        # Convert weeks to days
        $days += $weeks * 7

        # Convert days to hours
        $hours += $days * 24

        # Handle overflow in time units
        if ($seconds -ge 60) {
            $minutes += [math]::Floor($seconds / 60)
            $seconds = $seconds % 60
        }
        if ($minutes -ge 60) {
            $hours += [math]::Floor($minutes / 60)
            $minutes = $minutes % 60
        }

        # Ensure all values are properly converted to integers before formatting
        $hours = [int]$hours
        $minutes = [int]$minutes
        $seconds = [int]$seconds

        # Format as "HH:mm:ss" ensuring all values are properly converted to two-digit format
        return "{0:D2}:{1:D2}:{2:D2}" -f $hours, $minutes, $seconds
    }
    return "00:00:00"
}

# Function to convert ISO 8601 time duration to total seconds
function Convert-IsoDurationToSeconds($isoDuration) {
    if ($isoDuration -match '^P(?:(\d+)W)?(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$') {
        $weeks = if ($matches[1]) { [int]$matches[1] } else { 0 }
        $days = if ($matches[2]) { [int]$matches[2] } else { 0 }
        $hours = if ($matches[3]) { [int]$matches[3] } else { 0 }
        $minutes = if ($matches[4]) { [int]$matches[4] } else { 0 }
        $seconds = if ($matches[5]) { [math]::Round([decimal]$matches[5]) } else { 0 }

        # Convert weeks to days
        $days += $weeks * 7

        # Calculate total seconds
        return ($days * 86400) + ($hours * 3600) + ($minutes * 60) + [math]::Round($seconds)
    }
    return 0
}

function Convert-IsoDurationToSecondsToExcelTimeValue($isoDuration) {
	$seconds = Convert-IsoDurationToSeconds($isoDuration)
	return $seconds/86400
}

# Function to convert ISO 8601 string to a local date string (YYYY-MM-DD)
function Convert-IsoDateTimeToLocalDate($isoDateTime) {
    try {
        # Remove fractions of a second (if present) and keep the 'Z'
        $isoDateTime = $isoDateTime -replace '\.\d+Z$', 'Z'
        # Parse the ISO string and convert to local time
        $dateTime = [datetime]::ParseExact($isoDateTime, 'yyyy-MM-ddTHH:mm:ssZ', $null).ToLocalTime()
        # Return the formatted date
        return $dateTime.ToString('yyyy-MM-dd')
    }
    catch {
        Write-Warning "Invalid time format for $isoDateTime. Skipping conversion."
        return $null
    }
}

# Function to convert ISO 8601 string to a local time string (HH:mm:ss)
function Convert-IsoDateTimeToLocalTime($isoDateTime) {
    try {
        $isoDateTime = $isoDateTime -replace '\.\d+Z$', 'Z'
        $dateTime = [datetime]::ParseExact($isoDateTime, 'yyyy-MM-ddTHH:mm:ssZ', $null).ToLocalTime()
        return $dateTime.ToString('HH:mm:ss')
    }
    catch {
        Write-Warning "Invalid time format for $isoDateTime. Skipping conversion."
        return $null
    }
}

# Function to get the day of the week in English from an ISO 8601 string
function Convert-IsoDateTimeToDayOfWeek($isoDateTime) {
    try {
        # Define English day names
        $dayNamesEnglish = @('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')
        $isoDateTime = $isoDateTime -replace '\.\d+Z$', 'Z'
        $dateTime = [datetime]::ParseExact($isoDateTime, 'yyyy-MM-ddTHH:mm:ssZ', $null).ToLocalTime()
        return $dayNamesEnglish[$dateTime.DayOfWeek]
    }
    catch {
        Write-Warning "Invalid time format for $isoDateTime. Skipping conversion."
        return $null
    }
}

# Function to get the day of the week in Croatian from an ISO 8601 string
function Convert-IsoDateTimeToDayOfWeekCro($isoDateTime) {
    try {
        # Define Croatian day names
        $dayNamesCroatian = @('nedjelja', 'ponedjeljak', 'utorak', 'srijeda', 'cetvrtak', 'petak', 'subota')
        $isoDateTime = $isoDateTime -replace '\.\d+Z$', 'Z'
        $dateTime = [datetime]::ParseExact($isoDateTime, 'yyyy-MM-ddTHH:mm:ssZ', $null).ToLocalTime()
        return $dayNamesCroatian[$dateTime.DayOfWeek]
    }
    catch {
        Write-Warning "Invalid time format for $isoDateTime. Skipping conversion."
        return $null
    }
}

# Function to convert ISO 8601 date/time eg. "yyyy-MM-ddTHH:mm:ss+HH:mm" format to Zulu by same ISO spec like "yyyy-MM-ddTHH:mm:ssZ"
function Convert-IsoDateTimeToZulu($isoDateTime) {
    
    # Try parsing the input date-time
    try {
        # Parse the input date-time string
        $dateTime = [datetime]::Parse($isoDateTime)
        
        # Convert to UTC and then format to ISO 8601 Zulu time (ending with Z)
        $zuluTime = $dateTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        
        return $zuluTime
    }
    catch {
        Write-Host "Invalid date-time format provided $isoDateTime. Please provide a valid ISO 8601 date-time." -ForegroundColor Red
        exit 1
    }
}

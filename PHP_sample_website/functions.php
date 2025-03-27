<?php
/**
 * File: functions.php
 * 
 * 3CX XAPI Data Export Tool - Core Functions
 * 
 * This file contains all core functions for interacting with the 3CX XAPI,
 * including:
 * - API authentication and token management
 * - Data fetching and processing
 * - Swagger definition regeneration
 * - Export file generation (CSV/XLSX)
 * - Dynamic form configuration
 * 
 * Key Features:
 * - Handles all API communication with 3CX PBX
 * - Provides data parsing and transformation
 * - Manages session data and warnings
 * - Supports both CSV and Excel exports
 * - Includes comprehensive error handling
 * 
 * Dependencies:
 * - config.php for API credentials and settings
 * - definitions.php for endpoint configurations
 * - PhpSpreadsheet library for Excel export
 * 
 * Note: Requires PHP 7.4+ with cURL and JSON extensions
 */

require_once 'config.php'; // Include the configuration file with API credentials and settings.

// Initialize session with check for existing session
if(!isset($_COOKIE["PHPSESSID"])) {
    /**
     * SESSION INITIALIZATION
     * 
     * Starts or resumes the PHP session only if not already active.
     * Used to store:
     * - API warnings and messages
     * - Temporary file paths
     * - Rate limiting timestamps
     */
    session_start();
}

// Initialize warnings array to store any warning messages during execution
$_SESSION['warnings'] = [];

/**
 * Regenerate API definitions from PBX Swagger specification
 * 
 * This function downloads the Swagger YAML from the PBX, converts it to JSON,
 * and generates PHP definitions for API endpoints. Used for maintaining up-to-date
 * API definitions when PBX is updated.
 *
 * @param string|null $pbxUrl Optional custom PBX URL (uses XAPI_URL from config if null)
 * @param string $swaggerPath Path to Swagger YAML on PBX (default: '/xapi/v1/swagger.yaml')
 * @return bool Returns true on success, throws Exception on failure
 * @throws Exception If any step in the regeneration process fails
 */
function regenerateDefinitionsFromPBX($pbxUrl = null, $swaggerPath = '/xapi/v1/swagger.yaml') {
    // Determine PBX URL - use parameter if provided, otherwise fall back to config constant
    $pbxUrl = $pbxUrl ?? (defined('XAPI_URL') ? XAPI_URL : null);
    if (!$pbxUrl) {
        throw new Exception("(regen) XAPI_URL not defined and no fallback URL provided.");
    }

    // Define local file names for processing
    $localYaml = 'swagger.yaml';  // Local copy of downloaded YAML
    $localJson = 'swagger.json';  // Converted JSON version
    $generateScript = 'generate_definitions.php';  // Script to generate final definitions

    // Construct full URL to PBX's Swagger YAML
    $fullUrl = rtrim($pbxUrl, '/') . $swaggerPath;

    // Download swagger.yaml from PBX
    $yamlContent = @file_get_contents($fullUrl);
    if ($yamlContent === false) {
        throw new Exception("(regen) Failed to fetch swagger.yaml from PBX at $fullUrl");
    }
    if (file_put_contents($localYaml, $yamlContent) === false) {
        throw new Exception("(regen) Failed to write local swagger.yaml");
    }

    // Optional debug output: show system PATH (helps diagnose command availability issues)
    if (XAPI_DEBUG) {
        $path = getenv('PATH');
        $paths = explode(';', $path);
        echo "<pre>(debug) PATH entries:\n";
        foreach ($paths as $entry) {
            echo " - $entry\n";
        }
        echo "</pre>";
    }

    // Try to convert YAML to JSON using external tool
    try {
        // Validate YAML2JSON_PATH configuration
        if (strpos(YAML2JSON_PATH, DIRECTORY_SEPARATOR) !== false && !is_file(YAML2JSON_PATH)) {
            throw new Exception("(regen) YAML2JSON_PATH is not a valid file: " . YAML2JSON_PATH);
        }

        if (XAPI_DEBUG) {
            echo "(regen) YAML2JSON exists at: " . YAML2JSON_PATH . "\n";
        }

        // Test yaml2json availability with version check
        $testCmd = '"' . YAML2JSON_PATH . '" --version 2>&1';
        exec($testCmd, $testOutput, $testCode);
        if ($testCode !== 0 || empty($testOutput)) {
            throw new Exception("(regen) YAML2JSON test command failed. Output:\n" . implode("\n", $testOutput));
        }

        if (XAPI_DEBUG) {
            $versionLine = trim($testOutput[0]);
            echo "(regen) YAML2JSON test command succeeded. Version: $versionLine\n";
        }

        // Convert YAML to JSON using the configured tool
        $cmd = YAML2JSON_PATH . " $localYaml > $localJson 2>&1";
        exec($cmd, $output, $exitCode);
        if ($exitCode !== 0 || !file_exists($localJson) || filesize($localJson) === 0) {
            $outputText = implode("\n", $output);
            throw new Exception("(regen) YAML-to-JSON conversion failed (exit code $exitCode).\nCommand: $cmd\nOutput:\n$outputText");
        }

        if (XAPI_DEBUG) {
            echo "(regen) YAML-to-JSON conversion succeeded.\n";
        }

    } catch (Exception $e) {
        die("(regen) Error during swagger conversion: " . $e->getMessage());
    }

    // Run definitions generator script to create PHP definitions
    $generateCmd = PHP_CLI . " $generateScript 2>&1";
    exec($generateCmd, $output, $exitCode);
    if (!file_exists('definitions.php') || filesize('definitions.php') === 0) {
        throw new Exception("(regen) definitions.php generation failed or empty");
    }

    if (XAPI_DEBUG) {
        echo "(regen) definitions.php successfully generated.\n";
    }

    return true;
}

/**
 * Generate JavaScript configuration for dynamic form behavior
 * 
 * Analyzes endpoint configurations to determine which form fields (queuedn, from, to)
 * should be shown for each endpoint. Outputs as JavaScript object for client-side use.
 *
 * @param array $columnsPerEndpoint Array of endpoints and their columns
 * @return void Outputs JavaScript directly
 */
function outputJsEndpointConfig(array $columnsPerEndpoint): void {
    // Define tokens that trigger showing specific form fields
    $dnPlaceholders = ['{queuedn}', '{queueDn}', '{dnNumber}', '{number}']; // Tokens that trigger showing queuedn
    $fromPlaceholders = ['{from}', '{fromZulu}']; // Tokens that trigger showing "from"
    $toPlaceholders = ['{to}', '{toZulu}'];       // Tokens that trigger showing "to"
    
    $config = []; // Initialize configuration array

    global $endpointConfigs; // Access global endpoint configurations

    // Process each endpoint to determine required fields
    foreach ($columnsPerEndpoint as $endpoint => $columns) {
        $entry = []; // Initialize entry for this endpoint

        // Get endpoint configuration details
        $configInfo = $endpointConfigs[$endpoint] ?? [];
        $params = $configInfo['params'] ?? [];
        $url = $configInfo['url'] ?? '';

        // Combine all strings that might contain placeholder tokens
        $checkStrings = array_merge(array_values($params), [$url]);

        // Check if queuedn field should be shown
        foreach ($checkStrings as $str) {
            foreach ($dnPlaceholders as $needle) {
                if (stripos($str, $needle) !== false) {
                    $entry['show'][] = 'queuedn';
                    break 2; // Break both loops if found
                }
            }
        }

        // Check if 'from' field should be shown
        foreach ($checkStrings as $str) {
            foreach ($fromPlaceholders as $needle) {
                if (stripos($str, $needle) !== false) {
                    $entry['show'][] = 'from';
                    break 2;
                }
            }
        }
        
        // Check if 'to' field should be shown
        foreach ($checkStrings as $str) {
            foreach ($toPlaceholders as $needle) {
                if (stripos($str, $needle) !== false) {
                    $entry['show'][] = 'to';
                    break 2;
                }
            }
        }

        // Add to config if any fields need to be shown
        if (!empty($entry)) {
            $config[$endpoint] = $entry;
        }
    }

    // Output JavaScript configuration object, each endpoint on its own line with compact config block
    echo "const endpointConfig = {\n";
    foreach ($config as $endpoint => $settings) {
        echo "  \"$endpoint\": " . json_encode($settings, JSON_UNESCAPED_SLASHES) . ",\n";
    }
    echo "};\n";
}

/**
 * Retrieve XAPI authentication token
 * 
 * Uses client credentials flow to obtain an access token from the 3CX OAuth endpoint.
 * Token is required for all subsequent API requests.
 *
 * @return string Access token
 * @throws Exception If token request fails
 */
function getXAPIToken() {
    $tokenUrl = XAPI_URL . '/connect/token'; // Construct the token URL using the base API URL.
    
    // Prepare POST data for token request
    $postData = http_build_query([
        'client_id' => XAPI_USER,     // Client ID from config
        'client_secret' => XAPI_KEY,   // Client secret from config
        'grant_type' => 'client_credentials' // OAuth grant type
    ]);

    // Initialize cURL request
    $ch = curl_init($tokenUrl);
    curl_setopt($ch, CURLOPT_POST, true); // Set cURL to use POST method.
    curl_setopt($ch, CURLOPT_POSTFIELDS, $postData); // Attach the POST data.
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true); // Return the response as a string.
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Content-Type: application/x-www-form-urlencoded' // Required header for token request
    ]);
    curl_setopt($ch, CURLOPT_FAILONERROR, true); // Fail on HTTP errors
    
    // Handle SSL verification based on config
    if (defined('DISABLE_SSL_VERIFICATION') && DISABLE_SSL_VERIFICATION === true) {
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false); // Disable peer verification
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false); // Disable host verification
        if (XAPI_DEBUG) {
            $_SESSION['warnings'][] = "(token) SSL verification disabled (insecure - for testing only!)";
        }
    }
    
    // Execute token request
    $response = curl_exec($ch);

    // Handle cURL errors
    if (curl_errno($ch)) {
        $errorMessage = curl_error($ch); // Get the cURL error message.
        curl_close($ch); // Close the cURL session.
        $_SESSION['warnings'][] = "(token) cURL Error: " . $errorMessage . "<br>"; // Log the error.
        throw new Exception("(token)cURL Error: " . $errorMessage); // Throw an exception.
    }

    // Get HTTP status code
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch); // Close the cURL session.

    // Debug output for HTTP status code if debugging is enabled
    if (XAPI_DEBUG) {
        $_SESSION['warnings'][] = "(token) HTTP Status Code: " . $httpCode . "<br>"; // Log the status code
    }

    // Handle non-200 responses
    if ($httpCode !== 200) {
        if (XAPI_DEBUG) {
            $_SESSION['warnings'][] = "(token) Failed to retrieve access token. Response:<br><pre> " . $response . "</pre><br>"; // Log the response if debugging is enabled.
        }
        throw new Exception("(token) Failed to retrieve access token. HTTP Status Code: " . $httpCode); // Throw an exception.
    }

    // Parse JSON response
    $tokenData = json_decode($response, true);

    // Debug output for access token
    if (XAPI_DEBUG) {
        if (isset($tokenData['access_token'])) {
            $_SESSION['warnings'][] = "(token) Access Token Retrieved:<br><pre> " . $tokenData['access_token'] . "</pre><br>"; // Log the access token if debugging is enabled.
        } else {
            $_SESSION['warnings'][] = "(token) Failed to retrieve access token. Response:<br><pre> " . print_r($tokenData, true) . "</pre><br>"; // Log the response if no token is found.
        }
    }

    // Validate token exists in response
    if (!isset($tokenData['access_token'])) {
        throw new Exception("(token) Access token not found in response."); // Throw an exception if no token is found.
    }

    return $tokenData['access_token']; // Return the access token.
}

/**
 * Execute XAPI request to specified endpoint
 * 
 * Makes authenticated request to 3CX API endpoint and processes response.
 * Handles error checking, response validation, and data expansion.
 *
 * @param string $endpoint Endpoint name (for configuration lookup)
 * @param string $endpointuri Full endpoint URI path
 * @param array $params Query parameters
 * @return array Processed API response data
 * @throws Exception If request fails or response is invalid
 */
function invokeXAPIRequest($endpoint, $endpointuri, $params = []) {
    $queryString = ''; // Initialize query string builder

    // Manually build URL-encoded query string
    foreach ($params as $key => $value) {
        $queryString .= '&' . rawurlencode($key) . '=' . rawurlencode($value); // Append each parameter to the query string.
    }
    $queryString = ltrim($queryString, '&'); // Remove leading '&'

    // Construct full URL with query string if parameters exist
    $url = XAPI_URL . $endpointuri . (trim($queryString) !== '' ? '?' . $queryString : '');

    // Debug output for URL
    $_SESSION['warnings'][] = "(invoke) Making API request to: " . $url . "<br><br>URL decoded: " . urldecode($url) . "<br>";

    // Initialize cURL request
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Authorization: Bearer ' . getXAPIToken(), // Include access token
        'Accept: application/json' // Request JSON response
    ]);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true); // Return the response as a string.
    curl_setopt($ch, CURLOPT_FAILONERROR, true); // Fail on HTTP errors (4xx, 5xx).
    
    // Handle SSL verification based on config
    if (defined('DISABLE_SSL_VERIFICATION') && DISABLE_SSL_VERIFICATION === true) {
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
		if (XAPI_DEBUG) {
            $_SESSION['warnings'][] = "(invoke) SSL verification disabled (insecure - for testing only!)";
        }
    }
    
    // Execute request
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE); // Retrieve the HTTP status code.

    // Handle cURL errors
    if (curl_errno($ch)) {
        $errorMessage = curl_error($ch); // Get the cURL error message.
        curl_close($ch); // Close the cURL session.
        $_SESSION['warnings'][] = "(invoke) cURL Error: " . $errorMessage . "<br>"; // Log the error.
        // Only throw exception for transport-level failures (DNS, SSL, timeout, etc -> HTTP code is 0)
        if ($httpCode === 0 && $errorMessage) {
            throw new Exception("(invoke) cURL Error: " . $errorMessage); // Throw an exception only if connection truly failed
        }
    }

    curl_close($ch); // Close the cURL session.

    // Debug output for HTTP status
    $_SESSION['warnings'][] = "(invoke) HTTP Status Code: " . $httpCode . "<br>"; // Log the status code.

    // Handle special HTTP status codes
    if ($httpCode === 204) {
        throw new Exception("(invoke) Success: No content (HTTP 204). Endpoint returned no data to export which is valid response, not an error (endpoint has no data to return).");
    }
    elseif ($httpCode === 403) {
        // Special handling for 403 Forbidden (common when IP not whitelisted)
        if (XAPI_DEBUG) {
            echo "<div style='background-color: #fff3cd; padding: 10px; border-left: 4px solid #ffc107; margin-bottom: 10px;'>";
            echo "Access denied (403 Forbidden). This usually means your IP is not whitelisted on the 3CX server.<br>";
            echo "Please check the <strong>IP whitelist</strong> or <strong>Access Control</strong> settings in the 3CX management console.";
            echo "</div>";
        }
        throw new Exception("(invoke) API Request Failed. HTTP Status Code: 403 (Forbidden)");
    }
    elseif ($httpCode !== 200) {
        // Handle all other non-200 status codes
        if (XAPI_DEBUG) {
            $_SESSION['warnings'][] = "(invoke) API Request Failed. Response:<br><pre> " . $response . "</pre><br>"; // Log the response if debugging is enabled.
        }
        throw new Exception("(invoke) API Request Failed. HTTP Status Code: " . $httpCode); // Throw an exception.
    }

    // Parse JSON response
    $responseData = json_decode($response, true);

    // Debug output for response
    if (XAPI_DEBUG) {
        $_SESSION['warnings'][] = "(invoke) API Response:<br><pre> " . print_r($responseData, true) . "</pre><br>"; // Log the response if debugging is enabled.
    }

    // Handle empty or boolean responses
    if (empty($responseData)) {
        throw new Exception("(invoke) No data returned from API.");
    } elseif (isset($responseData['value']) && is_bool($responseData['value'])) {
        // Handle boolean-only responses (e.g. { "value": true } or { "value": false })
        echo "<p style='color:orange;'>(invoke) API only returned a boolean value: <strong>" . ($responseData['value'] ? 'true' : 'false') . "</strong>. Nothing further to process, show or export.</p>";
        exit;
    } else {
        testResponse($responseData); // Validate response structure
    }

    // Expand dataset with additional columns if 'value' exists
    if (isset($responseData['value'])) {
        $responseData['value'] = expandDataset($responseData['value'], $endpoint);
    }
    
    // Debug output for expanded response
    if (XAPI_DEBUG) {
        $_SESSION['warnings'][] = "(invoke) API Response with added columns:<br><pre> " . print_r($responseData, true) . "</pre><br>";
    }
    
    // Prepare for export
    global $endpointColumns;
    $useColumns = array_keys($endpointColumns[$endpoint]); // Use columns specified by $endpointColumns (definitions.php)
    
    // Debug output for export configuration
    if (XAPI_DEBUG) {
        $_SESSION['warnings'][] = "(export) Columns used: <br><pre>" . print_r($useColumns, true) . "<br>"; // Log the columns for debugging purposes
        $_SESSION['warnings'][] = "(export) File will be generated on disk in the following path: " . sys_get_temp_dir(); // Log the path of a file
    }

    // Display any accumulated warnings
    if (!empty($_SESSION['warnings'])) {
        foreach ($_SESSION['warnings'] as $warning) {
			// Display each warning in stylized DIV block.
            echo "<div style='background-color: #f8f9fa; padding: 10px; border-left: 4px solid #6c757d; font-style: italic; margin-bottom: 10px;'>$warning</div>";
        }
        unset($_SESSION['warnings']); // Clear warnings after display
    }

    echo "I will now show sample rows, and return dataset to export function, please be patient, for large datasets this can take a few minutes...";

	// Check if response includes ['value'] array that may be huge
	if (isset($responseData['value']) && is_array($responseData['value'])) {
		// if array, then slice only first 20 rows to $responseDataSample without duplicating whole array
		// set number of rows as limit
		$maxtablerows = 20;
		// set empty array
		$responseDataSample = [];

		// Copy all keys except 'value' to preserve them intact
		foreach ($responseData as $key => $val) {
			if ($key !== 'value') {
				$responseDataSample[$key] = $val;
			}
		}

		// Add sliced 'value' separately to preserve memory
		$responseDataSample['value'] = array_slice($responseData['value'], 0, $maxtablerows);
	} else {
		$responseDataSample = $responseData;
	}

    // Display sample data, as HTML table
	showSample($responseDataSample, $useColumns);

    return $responseData; // Return the response data.
}

/**
 * Parse ISO 8601 date/time string into components
 * 
 * Extracts date, time, and day names (English and Croatian) from ISO format.
 * Used for expanding datetime fields in API responses.
 *
 * @param string $isoDateTime ISO 8601 formatted datetime string
 * @return array|null Parsed components or null if invalid
 */
function parseIsoDateTime($isoDateTime) {
    if (empty($isoDateTime)) {
        return null; // Return null if the input is empty.
    }

    try {
        // Create DateTime object from ISO string (UTC timezone)
        $dateTime = new DateTime($isoDateTime, new DateTimeZone('UTC'));
        
        // Extract basic components - date, time, day of week
        $date = $dateTime->format('Y-m-d');
        $time = $dateTime->format('H:i:s');
        $dayOfWeekEnglish = $dateTime->format('l'); // Full day name in English

        // Check for Intl PHP extension (required for Croatian localization)
        if (!extension_loaded('intl')) {
            throw new Exception('(parseIsoDateTime) The Intl extension is required for Croatian day names.');
        }
        
        // Format day name in Croatian
        $formatter = new IntlDateFormatter(
            'hr_HR',            // Croatian locale
            IntlDateFormatter::FULL, // Full format
            IntlDateFormatter::NONE, // No time formatting
            null,              // Default timezone
            null,              // Default calendar
            'EEEE'             // Pattern for full day name
        );
        $dayOfWeekCroatian = $formatter->format($dateTime); // Extract the day of the week in Croatian.

        return [
            'date' => $date,
            'time' => $time,
            'dayOfWeekEnglish' => $dayOfWeekEnglish,
            'dayOfWeekCroatian' => $dayOfWeekCroatian
        ]; // Return all the parsed components
    } catch (Exception $e) {
        return null; // Return null on any parsing errors
    }
}

/**
 * Parse ISO 8601 duration string into components
 * 
 * Converts duration format (e.g., PT1H30M) to seconds, hh:mm:ss, and readable format.
 * Used for expanding duration fields in API responses.
 *
 * @param string $isoDuration ISO 8601 formatted duration string
 * @return array|null Parsed components or null if invalid
 */
function parseIsoDuration($isoDuration) {
    if (empty($isoDuration) || !preg_match('/^P/', $isoDuration)) {
        return null; // Return null if the input is empty or not a valid ISO duration.
    }

    try {
        // Extract duration components using regex
		// previously:
	//	preg_match('/P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?/', $isoDuration, $matches); // worked
        preg_match('/P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)/', $isoDuration, $matches); // new suggestion

        // Map regex matches to components (default to 0 if missing)
        $years = isset($matches[1]) ? (int) $matches[1] : 0;
        $months = isset($matches[2]) ? (int) $matches[2] : 0;
        $weeks = isset($matches[3]) ? (int) $matches[3] : 0;
        $days = isset($matches[4]) ? (int) $matches[4] : 0;
        $hours = isset($matches[5]) ? (int) $matches[5] : 0;
        $minutes = isset($matches[6]) ? (int) $matches[6] : 0;
        $seconds = isset($matches[7]) ? (float) $matches[7] : 0;

        // Convert all components to total seconds
        $totalSeconds = ($years * 31536000) +    // 365 days/year
                       ($months * 2592000) +     // ~30 days/month
                       ($weeks * 604800) +       // 7 days/week
                       ($days * 86400) +        // 24 hours/day
                       ($hours * 3600) +
                       ($minutes * 60) +
                       round($seconds);          // Round fractional seconds

        // Convert total seconds to hh:mm:ss format
        $hh = floor($totalSeconds / 3600);
        $mm = floor(($totalSeconds % 3600) / 60);
        $ss = $totalSeconds % 60;

        // Construct human-readable format (excluding zero components)
        $formattedDuration = [];
        if ($years)   $formattedDuration[] = "{$years}Y";
        if ($months)  $formattedDuration[] = "{$months}M";
        if ($weeks)   $formattedDuration[] = "{$weeks}W";
        if ($days)    $formattedDuration[] = "{$days}D";
        if ($hours || $minutes || $seconds) {
            $timePart = sprintf('%02d:%02d:%02d', $hours, $minutes, $ss);
            $formattedDuration[] = "T$timePart";
        }
        $readable = implode('', $formattedDuration);

        return [
            'seconds' => $totalSeconds,
            'hhmmss' => sprintf('%02d:%02d:%02d', $hh, $mm, $ss),
            'readable' => $readable
        ]; // Return all the parsed components.
    } catch (Exception $e) {
        return null; // Return null if parsing fails.
    }
}

/**
 * Expand dataset with additional columns for datetime and duration fields
 * 
 * Processes API response data to add formatted versions of datetime and duration fields
 * based on endpoint configuration (definitions.php). Makes data more usable for reporting.
 *
 * @param array $data Original API response data
 * @param string $endpoint Endpoint name (for configuration lookup)
 * @return array Expanded dataset with additional columns
 * @throws Exception If endpoint configuration is invalid
 */
function expandDataset($data, $endpoint) {
    global $endpointColumns; // Access column definitions from definitions.php

    // Validate endpoint configuration exists in definitions
    if (!isset($endpointColumns[$endpoint])) {
        throw new Exception("Endpoint '$endpoint' not found in column definitions.");
    }

    $columnTypes = $endpointColumns[$endpoint]; // Get column types for this endpoint
    $expandedData = $data; // Initialize expanded dataset

    // Process each row to add formatted columns
    foreach ($expandedData as &$row) {
        foreach ($columnTypes as $key => $type) {
            if (!isset($row[$key])) {
                continue; // Skip missing fields
            }

            // Handle ISO 8601 datetime fields
            if ($type === 'datetime') {
                $parsed = parseIsoDateTime($row[$key]); // Parse ISO 8601 datetime.
                if ($parsed) {
                    $row[$key . '_date'] = $parsed['date']; // Add date column.
                    $row[$key . '_time'] = $parsed['time']; // Add time column.
                    $row[$key . '_dayOfWeekEnglish'] = $parsed['dayOfWeekEnglish']; // Add English day of the week.
                    $row[$key . '_dayOfWeekCroatian'] = $parsed['dayOfWeekCroatian']; // Add Croatian day of the week.
                }
            } 
            // Handle ISO 8601 duration fields
            elseif ($type === 'duration') {
                $parsed = parseIsoDuration($row[$key]); // Parse ISO 8601 duration.
                if ($parsed) {
                    $row[$key . '_seconds'] = $parsed['seconds']; // Add seconds column.
                    $row[$key . '_hhmmss'] = $parsed['hhmmss']; // Add hh:mm:ss column.
                }
            }
        }
    }

    return $expandedData; // Return the expanded dataset.
}

/**
 * Prepare data for export by normalizing structure and expanding headers
 * 
 * Shared helper function for CSV and Excel exporters. Ensures consistent data structure,
 * handles missing values, and prepares expanded column headers for added columns.
 *
 * @param array $data API response data
 * @param string $endpoint Endpoint name (for configuration lookup)
 * @return array Prepared data with headers and normalized rows
 * @throws Exception If endpoint configuration is invalid
 */
function prepareExportData($data, $endpoint) {
    global $endpointColumns; // Access column definitions from definitions.php

    // Validate endpoint configuration exists in definitions
    if (!isset($endpointColumns[$endpoint])) {
        throw new Exception("Endpoint '$endpoint' not found in column definitions.");
    }

    // Generate expanded headers based on column types
    $headers = [];
    foreach ($endpointColumns[$endpoint] as $header => $type) {
        $headers[] = $header; // Base header
        
        // Add datetime sub-headers
        if ($type === 'datetime') {
            $headers[] = $header . '_date';
            $headers[] = $header . '_time';
            $headers[] = $header . '_dayOfWeekEnglish';
            $headers[] = $header . '_dayOfWeekCroatian';
        } 
        // Add duration sub-headers
        elseif ($type === 'duration') {
            $headers[] = $header . '_seconds';
            $headers[] = $header . '_hhmmss';
        }
    }

    // Normalize data rows (fill missing values, flatten arrays)
    $normalizedData = [];
    if (!empty($data['value'])) {
        foreach ($data['value'] as $row) {
            $normalizedRow = [];
            foreach ($headers as $header) {
                // Handle missing values
                $value = $row[$header] ?? '';
                
                // Flatten array values to JSON strings
                if (is_array($value)) {
                    $value = json_encode($value);
                }

                $normalizedRow[$header] = $value;
            }
            $normalizedData[] = $normalizedRow;
        }
    }

    return [
        'headers' => $headers,
        'normalizedData' => $normalizedData,
    ];
}

/**
 * Export data to CSV file
 * 
 * Generates CSV file from API response data with proper formatting,
 * handling of special characters, and expanded columns.
 *
 * @param array $data API response data
 * @param string $filename Output file path
 * @param string $endpoint Endpoint name (for configuration)
 * @return void Creates CSV file on disk
 */
function exportToCSV($data, $filename, $endpoint) {
    // Prepare data using shared helper function
    $exportData = prepareExportData($data, $endpoint);
    $headers = $exportData['headers'];
    $normalizedData = $exportData['normalizedData'];

    // Open file for writing
    $file = fopen($filename, 'w');

    // Write UTF-8 BOM for Excel compatibility
    fwrite($file, "\xEF\xBB\xBF");
    
    // Write header row
    fputcsv($file, $headers, ',', '"', '\\');

    // Write data rows
    foreach ($normalizedData as $row) {
        fputcsv($file, $row, ',', '"', '\\');
    }

    fclose($file); // Close the file.
}

/**
 * Export data to Excel (XLSX) file
 * 
 * Generates Excel file from API response data using PhpSpreadsheet.
 * Handles formatting, column widths, and expanded columns.
 *
 * @param array $data API response data
 * @param string $filename Output file path
 * @param string $endpoint Endpoint name (for configuration)
 * @return void Creates XLSX file on disk
 */
function exportToExcel($data, $filename, $endpoint) {
    // Prepare data using shared helper function
    $exportData = prepareExportData($data, $endpoint);
    $headers = $exportData['headers'];
    $normalizedData = $exportData['normalizedData'];

    // Load PhpSpreadsheet library
    require 'vendor/autoload.php';
    
    // Create new spreadsheet
    $spreadsheet = new \PhpOffice\PhpSpreadsheet\Spreadsheet();
    $sheet = $spreadsheet->getActiveSheet(); // Get the active sheet.

    // Add headers with styling
    $sheet->fromArray([$headers], null, 'A1');
    
    // Apply header styling
    $headerStyle = [
        'font' => ['bold' => true],
        'fill' => [
            'fillType' => \PhpOffice\PhpSpreadsheet\Style\Fill::FILL_SOLID,
            'color' => ['rgb' => 'F2F2F2']
        ]
    ];
    $sheet->getStyle('A1:' . $sheet->getHighestColumn() . '1')->applyFromArray($headerStyle);

    // Add data rows starting from the second row
    $sheet->fromArray($normalizedData, null, 'A2');

    // Auto-size columns for better readability
    foreach (range('A', $sheet->getHighestColumn()) as $col) {
        $sheet->getColumnDimension($col)->setAutoSize(true);
    }

    // Save spreadsheet to file
    $writer = new \PhpOffice\PhpSpreadsheet\Writer\Xlsx($spreadsheet);
    $writer->save($filename); // Save the spreadsheet to the specified file
}

/**
 * Validate API response structure and content
 * 
 * Performs various checks on API response to ensure data quality
 * and provide feedback about potential issues.
 *
 * @param array $data API response data
 * @return void May add warnings to session or throw exceptions
 * @throws Exception If response structure is invalid
 */
function testResponse($data) {
    // Case 1: Standard list response with "value" array
    if (isset($data['value'])) {
        if (!is_array($data['value'])) {
            $type = gettype($data['value']);
            throw new Exception("(test) 'value' is not an array but a {$type} with value " . var_export($data['value'], true) . ". Nothing to export.");
        }

        if (empty($data['value'])) {
            throw new Exception('(test) No data returned from API.'); // Throw an exception if no data is returned
        }

        // Calculate record counts
        $totalRecords = count($data['value']); // Count the total records in the response
        $totalFilteredRecords = $data['@odata.count'] ?? $totalRecords; // Get the total filtered count that XAPI should return (if available

        // Handle empty dataset cases
        if ($totalFilteredRecords === 0) {
            throw new Exception('(test) No data matching this filter.'); // Throw an exception if no data matches the filter.
        }

        if ($totalRecords === 0) {
            throw new Exception('(test) No data fetched from API.'); // Throw an exception if no data is fetched.
        }

        // Check for partial dataset (pagination)
        if ($totalFilteredRecords !== $totalRecords) {
            $_SESSION['warnings'][] = "(test) Warning: The dataset has been partially fetched ( $totalRecords / $totalFilteredRecords ). Consider increasing the 'top' parameter or keep in mind to use 'top'/'skip' for pagination.\n";
        } else {
            $_SESSION['warnings'][] = "(test) OK: The complete dataset has been fetched ( $totalRecords / $totalFilteredRecords ).\n"; // Log a success message.
        }

    // Case 2: Flat object response (no "value" array)
    } elseif (is_array($data)) {
        $keys = array_keys($data);
        $summary = implode(', ', array_slice($keys, 0, 5));
        $_SESSION['warnings'][] = "(test) Received object-style response with keys: $summary ...\n"; // Log a quick summary of keys in the flat object
        
        // Store flat object for potential export
        $_SESSION['flatObject'] = $data;

    // Case 3: Unexpected response type
    } else {
        throw new Exception('(test) Unexpected API response structure.');
    }
}

/**
 * Display sample data in HTML table
 * 
 * Renders a preview of API data in browser with proper formatting
 * and handling of different response types.
 *
 * @param array $data API response data
 * @param array $columns Columns to display
 * @return void Outputs HTML directly
 */
function showSample($data, $columns = []) {
    echo "<h3>(sample) Sample data:</h3>"; // Display a heading for the sample data.

    // Case 1: Flat object response (no "value" array)
    if (!isset($data['value']) && is_array($data)) {
        echo "<p>(flat) Flat object-style response detected. Displaying as a single row.</p>";

        // Start HTML table
        echo "<table border='1' cellpadding='5' cellspacing='0' style='border-collapse: collapse;'>";

        // Display headers
        echo "<thead><tr>";
        foreach (array_keys($data) as $key) {
            echo "<th style='background-color: #f2f2f2; font-weight: bold; text-transform: uppercase;'>$key</th>";
        }
        echo "</tr></thead>";

        // Display single row with values
        echo "<tbody><tr>";
        foreach ($data as $value) {
            if (is_array($value)) {
                $value = json_encode($value);
            }
            echo "<td>" . htmlspecialchars($value) . "</td>";
        }
        echo "</tr></tbody>";

        echo "</table>"; // End the table
        return;
    }

    // Case 2: Standard array response with 'value'
    $maxtablerows = 20; // Maximum rows to display in sample
    $sample = array_slice($data['value'], 0, $maxtablerows); // Get the first rows of data as defined by $maxtablerows

    echo "<p>(sample array / value) Array response detected with populated [value]. Displaying as a table with up to $maxtablerows rows.</p>";
    
    // Start HTML table
    echo "<table border='1' cellpadding='5' cellspacing='0' style='border-collapse: collapse;'>";

    // Display column headers
    echo "<thead><tr>";
    foreach ($columns as $col) {
        echo "<th style='background-color: #f2f2f2; font-weight: bold; text-transform: uppercase;'>$col</th>";
    }
    echo "</tr></thead>";

    // Display sample rows
    echo "<tbody>";
    foreach ($sample as $row) {
        echo "<tr>";
        foreach ($columns as $col) {
            // Display each cell value. Watch for array vs string
            $value = $row[$col] ?? 'N/A';
            if (is_array($value)) {
                $value = json_encode($value); // safer for HTML
            }
            echo "<td>" . htmlspecialchars($value) . "</td>";
        }
        echo "</tr>";
    }
    echo "</tbody>";

    echo "</table>"; // End the HTML table
}

/**
 * Fetch data from specified API endpoint
 * 
 * Main function for retrieving data from 3CX API. Handles parameter substitution,
 * date formatting, and request execution.
 *
 * @param string $endpoint Endpoint name (from configuration)
 * @param string $from Start date (YYYY-MM-DD)
 * @param string $to End date (YYYY-MM-DD)
 * @param string $queuedn Queue DN/extension
 * @param int $top Maximum records to return
 * @param int $skip Records to skip (pagination)
 * @return array API response data
 */
function getData($endpoint, $from, $to, $queuedn, $top, $skip) {
    global $endpointConfigs; // Access column definitions from definitions.php

    try {
        // Validate endpoint configuration exists in definitions
        if (!isset($endpointConfigs[$endpoint])) {
            throw new Exception("Endpoint '$endpoint' is not supported.");
        }

        // Get endpoint configuration
        $config = $endpointConfigs[$endpoint];

        // Convert dates to Zulu time if required by endpoint
        $fromZulu = $config['zulu'] ? "$from" . "T00:00:00Z" : $from;
        $toZulu = $config['zulu'] ? "$to" . "T23:59:59Z" : $to;

        // Get URL and parameters from config
        $url = $config['url'];
        $params = $config['params'];
        
        // Replace placeholders in URL
        $url = str_replace(
            ['{from}', '{to}', '{skip}', '{top}', '{fromZulu}', '{toZulu}', '{queuedn}', '{dnNumber}', '{number}'],
            [$from, $to, $skip, $top, $fromZulu, $toZulu, $queuedn, "'".$queuedn."'", "'".$queuedn."'"],
            $url
        );

        // Replace placeholders in parameters
        foreach ($params as $key => $value) {
            $params[$key] = str_replace(
                ['{from}', '{to}', '{skip}', '{top}', '{fromZulu}', '{toZulu}', '{queuedn}', '{dnNumber}'],
                [$from, $to, $skip, $top, $fromZulu, $toZulu, $queuedn, $queuedn],
                $value
            );
        }

        // // Add $skip and $top to the parameters.
        // $params['$count'] = 'true';
        // $params['$skip'] = $skip;
        // $params['$top'] = $top;

        // Execute API request
        $response = invokeXAPIRequest($endpoint, $url, $params);
        
        return $response; // Return the response
    } catch (Exception $e) {
        // Log error for display
        $_SESSION['warnings'][] = "Error in getData ($endpoint): " . $e->getMessage();

        // Return empty array to allow graceful failure
        return [];
    }
}

?>
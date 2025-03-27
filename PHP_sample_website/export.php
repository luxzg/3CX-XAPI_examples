<?php
/**
 * File: export.php
 * Purpose: Handles data export functionality from API to CSV/XLSX formats
 * 
 * This script:
 * 1. Sets up debugging configuration
 * 2. Implements rate limiting
 * 3. Validates and sanitizes all user input
 * 4. Fetches data from the API
 * 5. Generates temporary export files
 * 6. Provides download capability
 * 
 * Security Note: All user input is thoroughly validated and sanitized
 */

// Load configuration first to ensure constants like XAPI_DEBUG are available
// This must come before any other code that might use these constants
require_once 'config.php';

/**
 * DEBUGGING CONFIGURATION
 * 
 * When XAPI_DEBUG is true:
 * - All errors are reported (E_ALL)
 * - Errors are displayed directly in the browser
 * 
 * Important: Always set XAPI_DEBUG to false in production!
 * This prevents sensitive information from being exposed
 */
if (defined('XAPI_DEBUG') && XAPI_DEBUG === true) {
    // Report all PHP errors, warnings, and notices
    error_reporting(E_ALL);
    // Display errors directly in the browser output
    ini_set('display_errors', 1);
}

// Load helper functions and session management logic
require_once 'functions.php';
// Load endpoint-specific definitions generated from Swagger documentation
require_once 'definitions.php';

/**
 * RATE LIMITING IMPLEMENTATION
 * 
 * Prevents abuse of the export functionality by:
 * - Tracking last request time in session
 * - Enforcing a minimum delay between requests (XAPI_RATELIMIT)
 * - Blocking requests that come too quickly
 */
if (defined('XAPI_RATELIMIT')) {
    // Initialize last request timestamp if not set
    if (!isset($_SESSION['last_request'])) {
        $_SESSION['last_request'] = time();
    } 
    // Check if request comes too soon after previous request
    elseif (time() - $_SESSION['last_request'] < XAPI_RATELIMIT) {
        // Block the request and show error message
        die("Please wait a little before making another request. Limit set to " . XAPI_RATELIMIT . " seconds <a href='index.html'>Back to input form</a>");
    }
    // Update last request time for the current request
    $_SESSION['last_request'] = time();
}

// Initialize array to collect validation errors
// This provides better user feedback than failing on first error
$validationErrors = [];

/**
 * INPUT VALIDATION SECTION
 * 
 * Each input is:
 * 1. Retrieved from POST data
 * 2. Sanitized or validated
 * 3. Checked for business logic validity
 * 
 * All errors are collected rather than failing immediately
 */

// Validate and sanitize endpoint selection
$endpoint = filter_input(INPUT_POST, 'endpoint', FILTER_SANITIZE_FULL_SPECIAL_CHARS);
if (!$endpoint) {
    $validationErrors[] = "Invalid endpoint selected.";
} else {
    // Store valid endpoint in session for later use
    $_SESSION['endpoint'] = $endpoint;
}

// Validate 'from' date (optional)
$from = filter_input(INPUT_POST, 'from', FILTER_SANITIZE_FULL_SPECIAL_CHARS);
if ($from && !preg_match('/^\d{4}-\d{2}-\d{2}$/', $from)) {
    $validationErrors[] = "Invalid 'from' date format. Expected YYYY-MM-DD.";
}

// Validate 'to' date (optional)
$to = filter_input(INPUT_POST, 'to', FILTER_SANITIZE_FULL_SPECIAL_CHARS);
if ($to && !preg_match('/^\d{4}-\d{2}-\d{2}$/', $to)) {
    $validationErrors[] = "Invalid 'to' date format. Expected YYYY-MM-DD.";
}

/**
 * DATE RANGE VALIDATION
 * 
 * Additional checks when both dates are provided:
 * - Verify dates can be parsed
 * - Ensure from date <= to date
 */
if ($from && $to) {
    $fromTimestamp = strtotime($from);
    $toTimestamp = strtotime($to);

    // Basic date parsing validation
    if ($fromTimestamp === false || $toTimestamp === false) {
        $validationErrors[] = "Invalid date provided.";
    }

    // Logical date range validation, if 'from' date is greater than 'to' date
    if ($fromTimestamp > $toTimestamp) {
        $validationErrors[] = "The 'from' date must be earlier than or equal to the 'to' date.";
    }
}

// Validate 'top' parameter (max records to retrieve)
$top = filter_input(INPUT_POST, 'top', FILTER_VALIDATE_INT, ['options' => ['min_range' => 0]]);
if ($top === false) {
    $validationErrors[] = "Invalid value for 'top'. Must be a non-negative integer.";
}

// Validate 'skip' parameter (pagination offset)
$skip = filter_input(INPUT_POST, 'skip', FILTER_VALIDATE_INT, ['options' => ['min_range' => 0]]);
if ($skip === false) {
    $validationErrors[] = "Invalid value for 'skip'. Must be a non-negative integer.";
}

// Validate optional 'queuedn' parameter (Queue DN)
$queuedn = filter_input(INPUT_POST, 'queuedn', FILTER_VALIDATE_INT, ['options' => ['min_range' => 0]]) ?? ''; // defaulting to an empty string if not provided

// Validate export format selection: csv or xlsx
$format = filter_input(INPUT_POST, 'format', FILTER_SANITIZE_FULL_SPECIAL_CHARS);
if (!in_array($format, ['csv', 'xlsx'])) {
    $validationErrors[] = "Invalid export format selected.";
}

/**
 * VALIDATION ERROR HANDLING
 * 
 * If any validation errors occurred:
 * - Display all errors in a user-friendly format
 * - Provide a way back to the input form
 * - Terminate script execution
 */
if (!empty($validationErrors)) {
    echo "<html><body>";
    // Display each error in a styled div
    foreach ($validationErrors as $msg) {
        echo "<div style='background-color: #f8d7da; padding: 10px; border-left: 4px solid #dc3545; margin-bottom: 10px;'>" . htmlspecialchars($msg) . "</div>";
    }
    // Provide navigation back to input form
    echo "<a href='index.php'>Back to input form</a></body></html>";
    die();
}

/**
 * DATA PROCESSING SECTION
 * 
 * Begin main export functionality after successful validation
 */

// Start HTML output for the export page
echo "<html><body>";
echo "<h1>Data Preview & download</h1>";

// Main data processing try-catch block
try {
    /**
     * ENDPOINT VALIDATION
     * 
     * Verify the selected endpoint exists in our definitions
     * $endpointColumns comes from definitions.php
     */
    if (!isset($endpointColumns[$endpoint])) {
        // Log warning for troubleshooting
        $_SESSION['warnings'][] = "(export) Invalid endpoint selected : $endpoint.";
        throw new Exception('(export) Invalid endpoint selected.');
    }

    /**
     * API DATA FETCH
     * 
     * getData() is defined in functions.php and handles:
     * - API authentication
     * - Parameter formatting
     * - Error handling
     */
    $response = getData($endpoint, $from, $to, $queuedn, $top, $skip);

    // Check for empty response
    if (empty($response)) {
        // Log warning for troubleshooting
        $_SESSION['warnings'][] = "(export) No data available. Please check the warnings above and try again.";
        throw new Exception("(export) No data available. Please check the warnings above and try again.");
    }

    /**
     * TEMPORARY FILE GENERATION
     * 
     * Create a unique filename using:
     * - Prefix for identification
     * - Timestamp for uniqueness
     * - Session ID for security
     * - Proper extension based on format
     */
    $tempFilename = "temp_export_" . time() . "_" . session_id() . "." . ($format === 'csv' ? 'csv' : 'xlsx');
    // Store in system temp directory with proper directory separator
    $tempFilePath = sys_get_temp_dir() . DIRECTORY_SEPARATOR . $tempFilename;

    // Provide user feedback about file generation
    echo "Please wait, trying to export data to CSV/XLSX as selected... Temp file being generated... $tempFilePath ...\n";

    // Store file path in session for download.php to access
    $_SESSION['export_file'] = $tempFilePath;

    /**
     * FORMAT-SPECIFIC EXPORT
     * 
     * Call appropriate export function based on user selection
     */
    if ($format === 'csv') {
        exportToCSV($response, $tempFilePath, $endpoint); // Export data to a CSV file
    } elseif ($format === 'xlsx') {
        exportToExcel($response, $tempFilePath, $endpoint); // Export data to an Excel file
    }

    // Success message
    echo "Finished creating temp file!\n";

    /**
     * DOWNLOAD FORM
     * 
     * Provide button to initiate download via download.php
     */
    echo "<br>";
    echo "<form action='download.php' method='post'>";
    echo "<input type='submit' value='Download Full Data'>";
    echo "</form>";

} catch (Exception $e) {
    /**
     * ERROR HANDLING
     * 
     * Display any accumulated warnings first
     * Then show the fatal error message
     */
    if (!empty($_SESSION['warnings'])) {
        foreach ($_SESSION['warnings'] as $warning) {
            echo "<div style='background-color: #f8f9fa; padding: 10px; border-left: 4px solid #6c757d; font-style: italic; margin-bottom: 10px;'>$warning</div>";
        }
        // Clear warnings after displaying
        unset($_SESSION['warnings']);
    }

    // Terminate with error message
    die("Execution terminated, reason: " . $e->getMessage());
}

// Close HTML document
echo "</body></html>";
?>
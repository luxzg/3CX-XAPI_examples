<?php
/**
 * File: download.php
 * Purpose: Handles downloading of exported files to the client's browser
 * 
 * This script:
 * 1. Checks for an exported file in the session
 * 2. Validates the file exists on the server
 * 3. Prepares proper download headers
 * 4. Streams the file to the client
 * 5. Cleans up temporary files
 * 
 * Note: This is meant as an example for other developers with detailed comments
 */

// Start or resume existing session to access session variables
// This is necessary because we stored the file path in the session during export
session_start();

// Check if the export file path exists in the session
// This is a security check to prevent direct access to this script without proper file generation
if (!isset($_SESSION['export_file'])) {
    // Terminate script with error message if no file path was found
    // Provide a link back to the input form for better user experience
    die("File to download was not defined in this session, try to generate data again. <a href='index.html'>Back to input form</a>");
}

// Retrieve the full path to the exported file from session variable
// This path was stored during the export process in a previous script
$filePath = $_SESSION['export_file'];

// Verify the physical file exists on the server before attempting to download
// This prevents errors if the file was deleted or never created
if (!file_exists($filePath)) {
    // Terminate with error if file is missing
    // Again provide a way back to the input form
    die("File not found. It may have been deleted, try to generate data again. <a href='index.html'>Back to input form</a>");
}

// Get the endpoint name from session to use in the downloaded filename
// The endpoint typically indicates what type of data was exported (e.g., 'CallHistory')
// Use 'export' as default if endpoint isn't set in session
$endpoint = $_SESSION['endpoint'] ?? 'export';

// Create a user-friendly filename for the downloaded file by combining:
// 1. The endpoint name
// 2. The string '_export'
// 3. The original file extension
// Example result: "CallHistory_export.csv"
$filename = $endpoint . '_export.' . pathinfo($filePath, PATHINFO_EXTENSION);

// Prepare headers to force file download in the browser
// First set generic binary content type to ensure download rather than display
header('Content-Type: application/octet-stream');

// Set content disposition with our custom filename
// The 'attachment' parameter tells browser to download rather than display
header('Content-Disposition: attachment; filename="' . $filename . '"');

// Output the file contents directly to the output buffer
// This streams the file to the client's browser efficiently
readfile($filePath);

// Clean up the temporary file after successful download
// Important for security and to prevent accumulating temp files
unlink($filePath);

// Clear the session variable since we're done with this export
// This prevents duplicate downloads and keeps session clean
unset($_SESSION['export_file']);

/**
 * Cleans up old temporary export files from the server
 * 
 * This function removes temporary files that:
 * - Match the specified prefix pattern
 * - Are older than the specified maximum age
 * 
 * @param string $tempDir Directory to search for temp files
 * @param string $prefix File prefix pattern to match (default 'temp_export_')
 * @param float $maxAgeHours Maximum age in hours before deletion (default 1 hour)
 */
function cleanupOldTempFiles($tempDir, $prefix = 'temp_export_', $maxAgeHours = 1) {
    // Find all matching files with supported extensions (.csv or .xlsx)
    // GLOB_BRACE allows matching multiple patterns in one call
    $files = glob($tempDir . DIRECTORY_SEPARATOR . $prefix . '*.{csv,xlsx}', GLOB_BRACE);

    // Process each matching file
    foreach ($files as $file) {
        // Check if file modification time is older than our threshold
        // time() gives current timestamp, 3600 converts hours to seconds
        if (filemtime($file) < (time() - ($maxAgeHours * 3600))) {
            // Delete the outdated temporary file
            unlink($file);
        }
    }
}

// Execute cleanup at script completion
// Uses system temp directory and our standard prefix
// Note: Using 0.08 hours (~5 minutes) for testing/demo purposes
// In production, you might want to increase this (e.g., 24 hours)
cleanupOldTempFiles(sys_get_temp_dir(), 'temp_export_', 0.08);

?>
<?php
/**
 * File: index.php
 * Purpose: Main interface for 3CX XAPI Data Export Tool
 * 
 * This script:
 * 1. Checks if endpoint definitions need regeneration
 * 2. Loads required PHP files
 * 3. Provides a user interface for selecting export parameters
 * 4. Includes JavaScript for dynamic form behavior
 */

// Load helper functions first as they may be needed for definition regeneration
require_once 'functions.php';

/**
 * DEFINITION FILE VALIDATION
 * 
 * Regenerate definitions.php if:
 * 1. The file doesn't exist, OR
 * 2. The session doesn't have a last_request timestamp, OR
 * 3. The definitions are older than SWAGGER_AGE_LIMIT
 * 
 * This ensures we always have fresh endpoint definitions when needed
 */
if (
    !file_exists('definitions.php') ||          // If file is missing
    !isset($_SESSION['last_request']) ||        // Or session doesn't have timestamp
    (time() - $_SESSION['last_request']) > SWAGGER_AGE_LIMIT // Or too old
) {
    // Regenerate the definitions file by:
    // 1. Downloading fresh swagger.yaml from PBX
    // 2. Converting to swagger.json
    // 3. Creating new definitions.php
    regenerateDefinitionsFromPBX();
}

// Now include the freshly generated or existing definitions.php
// This provides $endpointConfigs and $endpointColumns variables
require_once 'definitions.php';
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>3CX XAPI Export Tool</title>
    <style>
        /* Basic styling for the interface */
        body { font-family: sans-serif; padding: 2em; }
        .hidden { display: none; }  /* Utility class for hiding elements */
        label { display: block; margin-top: 1em; font-weight: bold; }
    </style>
    
    <!-- JavaScript for dynamic form behavior -->
    <script>
    <?php 
    /**
     * OUTPUT JAVASCRIPT CONFIGURATION
     * 
     * Generates a JavaScript object containing endpoint configuration
     * This is used by the client-side code to manage form behavior
     */
    outputJsEndpointConfig($endpointColumns); 
    ?>

    /**
     * TOGGLE FIELD VISIBILITY
     * 
     * Updates visibility and required status of form fields based on:
     * - The currently selected endpoint
     * - The endpoint's configuration
     */
    function toggleFieldVisibility() {
        // Get the selected endpoint from dropdown
        const selectedEndpoint = document.getElementById("endpoint").value;
        
        // Get config for this endpoint or default to empty object
        const config = endpointConfig[selectedEndpoint] || {};
        
        // Fields that might need to be shown/hidden
        const fields = ['from', 'to', 'queuedn'];

        fields.forEach(field => {
            // Get DOM elements (fields, labels)
            const input = document.getElementById(field);
            const label = document.querySelector(`label[for="${field}"]`);
            
            // Check if this field should be shown
            const isShown = config.show && config.show.includes(field);

            // Toggle visibility and required status
            if (isShown) {
                input.classList.remove("hidden");  // Show field
                label.classList.remove("hidden");  // Show label
                input.required = true;            // Make required
            } else {
                input.classList.add("hidden");    // Hide field
                label.classList.add("hidden");    // Hide label
                input.required = false;           // Remove required
            }
        });
    }

    /**
     * INITIALIZE PAGE
     * 
     * Sets up event listeners and initial field states
     * Runs when DOM is fully loaded
     */
    window.addEventListener("DOMContentLoaded", function () {
        // Initialize field visibility with slight delay to ensure:
        // - Form values are properly restored after Back button
        // - All elements are definitely available
        setTimeout(toggleFieldVisibility, 1);

        // Update fields whenever endpoint selection changes
        document.getElementById("endpoint").addEventListener("change", toggleFieldVisibility);
    });
    </script>
</head>
<body>
    <!-- Main page heading -->
    <h1>3CX XAPI Data Export</h1>
    
    <!-- 
        Export form - submits to export.php
        All fields use POST method for better security with sensitive data
    -->
    <form action="export.php" method="POST">
        <!-- 
            ENDPOINT SELECTION 
            Dropdown populated from $endpointConfigs
        -->
        <label for="endpoint">Select Endpoint:</label>
        <select name="endpoint" id="endpoint" required autofocus>
            <?php
            // Populate dropdown with all available endpoints in definitions.php
            foreach ($endpointConfigs as $key => $_) {
                echo "<option value=\"$key\">$key</option>";
            }
            ?>
        </select><br><br>

        <!-- DATE RANGE FIELDS -->
        <!-- From date - shown/hidden based on endpoint -->
        <div id="fromContainer">
            <label for="from">From (YYYY-MM-DD):</label>
            <input type="date" name="from" id="from" class="hidden"><br><br>
        </div>

        <!-- To date - shown/hidden based on endpoint -->
        <div id="toContainer">
            <label for="to">To (YYYY-MM-DD):</label>
            <input type="date" name="to" id="to" class="hidden"><br><br>
        </div>

        <!-- PAGINATION FIELDS -->
        <!-- Top - always visible with default of 100 records -->
        <div id="topContainer">
            <label for="top">Top (max records):</label>
            <input type="number" name="top" id="top" value="100"><br><br>
        </div>

        <!-- Skip - always visible with default of 0 -->
        <div id="skipContainer">
            <label for="skip">Skip (records to skip):</label>
            <input type="number" name="skip" id="skip" value="0"><br><br>
        </div>

        <!-- QUEUE DN FIELD -->
        <!-- Only shown for endpoints that need it -->
        <div id="queuednContainer">
            <label for="queuedn">Phone / extension eg 1234 or 5000 for use with queue or fax or phone endpoints:</label>
            <input type="text" name="queuedn" id="queuedn" class="hidden"><br><br>
        </div>

        <!-- EXPORT FORMAT SELECTION -->
        <label for="format">Export Format:</label>
        <select name="format" id="format" required>
            <option value="csv">CSV</option>
            <option value="xlsx">Excel (XLSX)</option>
        </select><br><br>

        <!-- SUBMIT BUTTON -->
        <button type="submit" id="submitBtn">Get Data</button>
    </form>
</body>
</html>
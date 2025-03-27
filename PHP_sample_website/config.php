<?php
/**
 * File: config.php
 * Purpose: Configuration for 3CX XAPI integration
 * 
 * This file contains all system configuration including:
 * - Session security settings
 * - Debug and SSL verification flags
 * - API credentials and endpoints
 * - External binary paths
 * - Rate limiting parameters
 */

// Determine if the application is running over HTTPS by checking:
// 1. HTTPS header
// 2. Server port (443 = HTTPS)
$isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || 
           ($_SERVER['SERVER_PORT'] == 443);

/**
 * SESSION SECURITY CONFIGURATION
 * 
 * Critical security settings for PHP sessions:
 * - Secure cookies (HTTPS only)
 * - HTTP-only flag (prevent JS access)
 * - SameSite Strict (CSRF protection)
 */
if (!session_start([
    'cookie_secure'   => $isHttps,   // Send cookies only over HTTPS
    'cookie_httponly' => true,       // Prevent JavaScript cookie access
    'cookie_samesite' => 'Strict'    // Block cross-site requests
])) {
    die('Failed to start secure session.');
}

// Regenerate session ID to prevent session fixation attacks
if (!session_regenerate_id(true)) {
    die('Critical security failure: Session ID regeneration failed');
}

// Set session lifetime in seconds to reduce hijacking risk
define('SESSION_LIFETIME', 3600); // eg. to 1 hour (3600 seconds)
ini_set('session.gc_maxlifetime', SESSION_LIFETIME);
session_set_cookie_params(SESSION_LIFETIME);

/**
 * DEBUGGING CONFIGURATION
 * 
 * XAPI_DEBUG enables/disables diagnostic output:
 * - When true: Shows tokens, API responses, warnings
 * - When false: Production mode (no sensitive data exposed)
 * 
 * IMPORTANT: Always set to false in production!
 */
define('XAPI_DEBUG', false);

/**
 * SSL VERIFICATION
 * 
 * DISABLE_SSL_VERIFICATION controls cURL certificate validation:
 * - true: Bypass verification (for self-signed certs in testing)
 * - false: Enforce strict SSL verification (production)
 */
define('DISABLE_SSL_VERIFICATION', true);

/**
 * RATE LIMITING
 * 
 * XAPI_RATELIMIT sets minimum delay (seconds) between API requests
 * Prevents API abuse and server overload
 */
define('XAPI_RATELIMIT', 10); // eg. 10 seconds cooldown

/**
 * DEFINITION REFRESH
 * 
 * SWAGGER_AGE_LIMIT controls how often API definitions regenerate:
 * - Value in seconds (60 = 1 minute)
 * - Forces update of swagger/definition files when expired
 */
define('SWAGGER_AGE_LIMIT', 60); // eg. 60 seconds

/**
 * 3CX API CREDENTIALS
 * 
 * Replace placeholder values with your actual 3CX credentials:
 * - XAPI_USER: API client ID
 * - XAPI_KEY: API client secret
 * - XAPI_URL: PBX server URL with port (typically :5001)
 * 
 * SECURITY WARNING:
 * - Never commit real credentials to version control
 * - Consider storing these in environment variables
 */
define('XAPI_USER', 'your_3cx_api_username');				// Replace with actual API username
define('XAPI_KEY', 'your_3cx_api_secret');     				// Replace with actual API secret  
define('XAPI_URL', 'https://your_3cx_server.3cx.eu:5001');	// Replace with your PBX URL

/**
 * EXTERNAL BINARY PATHS
 * 
 * Required for Swagger processing:
 * - NODE_PATH: Full path to Node.js executable
 * - YAML2JSON_PATH: Full path to yaml2json converter
 * - PHP_CLI: Full path to PHP CLI
 * 
 * Installation examples:
 * 1. Install Node.js: scoop install nodejs-lts
 * 2. Install yaml2json: npm install -g yamljs
 * 3. Verify paths with: where node / where yaml2json or which node / which yaml2json
 * 
 * System settings:
 * - Ensure web server has permission to execute these binaries
 * - Ideally set system environmental variables to have PATH include location of these binaries
 */
define('NODE_PATH', 'node');          // e.g. 'C:/scoop/apps/nodejs-lts/current/node.exe'
define('YAML2JSON_PATH', 'yaml2json'); // e.g. 'C:/Users/You/AppData/Roaming/npm/yaml2json'
define('PHP_CLI', 'php');             // e.g. 'C:/scoop/apps/php/current/php.exe'

/**
 * SECURITY NOTES:
 * 1. In production place this file outside web root if possible
 * 2. Use .htaccess to restrict access
 * 3. For production:
 *    - Disable XAPI_DEBUG
 *    - Enable SSL verification
 *    - Use proper SSL certificates
 * 4. Rotate API credentials regularly
 */
?>
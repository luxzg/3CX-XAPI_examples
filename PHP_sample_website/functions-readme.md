# 📘 PHP Functions - 3CX XAPI Integration

This document outlines the core functions from `functions.php` that power the 3CX XAPI Export Tool.
These functions handle everything from authentication to data export.

---

## 🌟 Key Features
- **Automatic API Discovery**: Regenerates endpoint definitions from PBX Swagger specs
- **Smart Data Handling**: Expands datetime/duration fields
- **Flexible Export**: Supports CSV and Excel (XLSX) formats
- **Dynamic Forms**: JavaScript integration for endpoint-specific UI configuration
- **Comprehensive Error Handling**: Detailed warnings and validation

---

## 🔁 Session & Swagger Definitions

### `regenerateDefinitionsFromPBX($pbxUrl = null, $swaggerPath = '/xapi/v1/swagger.yaml')`

**Parameters:**
- `$pbxUrl` *(string|null)*: Optional PBX URL (uses `XAPI_URL` if not provided)
- `$swaggerPath` *(string)*: Path to Swagger YAML (default: `/xapi/v1/swagger.yaml`)

**Returns:** `true` on success

**Throws:** `Exception` on:
- Failed YAML download
- JSON conversion errors
- Invalid definition generation

**Logic:**  
Maintains up-to-date API definitions by processing Swagger specifications when:
- Definitions file is missing
- Session timestamp is expired
- Definitions are older than `SWAGGER_AGE_LIMIT`

Process Flow  
1. Downloads `swagger.yaml` from PBX
2. Converts to JSON using `yaml2json`
3. Generates PHP definitions
4. Performs post-processing normalization

**Requires:**
- Utility `yaml2json` (install via `npm install -g yamljs`)
- Uses `generate_definitions.php` for processing

---

## 🌐 JavaScript Integration

### `outputJsEndpointConfig(array $columnsPerEndpoint): void`
Generates a JavaScript configuration for dynamic form behavior based on endpoint requirements.

**Parameters:**
- `$columnsPerEndpoint` *(array)*: Endpoint column definitions

**Returns:** `void` (outputs JavaScript directly)

**Throws:** `Exception` on invalid endpoint configurations

**Logic:**
- Determines required fields for each endpoint
- Scans for `{queuedn}`, `{from}`, `{to}` placeholders
- Supports standard and Zulu date formats
- Outputs minimal JS configuration object

**Requires:**
- Global `$endpointConfigs` array from definitions.php
- Consistent parameter naming across endpoints

---

## 🔐 Authentication

### `getXAPIToken()`
Handles OAuth 2.0 client credentials flow to obtain access tokens.

**Returns:** `string` Access token

**Throws:** `Exception` on:
- Network errors (cURL)
- Invalid credentials (HTTP 401)
- PBX connectivity issues

**Logic:**
- Uses `XAPI_USER` and `XAPI_KEY` from config
- Fresh token per request (no caching)
- Optional SSL verification bypass (testing only)
- Implements proper error handling for:
  - Network failures
  - Invalid credentials
  - PBX connectivity issues
- Debug mode shows token details (`XAPI_DEBUG`)

**Requires:**
- Valid `XAPI_URL`, `XAPI_USER`, `XAPI_KEY` constants
- PHP cURL extension enabled

---

## 📡 API Requests

### `invokeXAPIRequest($endpoint, $endpointuri, $params = [])`
Core API communication handler with advanced features:

**Parameters:**
- `$endpoint` *(string)*: Endpoint identifier
- `$endpointuri` *(string)*: Complete endpoint URI
- `$params` *(array)*: Query parameters

**Returns:** `array` Parsed JSON response

**Throws:** `Exception` on:
- Transport failures
- Access denial (HTTP 403)
- Invalid responses

**Logic:**  
Special Handling:
- `HTTP 204 No Content` (valid empty responses)
- `HTTP 403 Forbidden` (IP whitelist guidance)
- Validates JSON structure
- Boolean-only responses
- Expands dataset with additional columns
- OData parameters (`$top`, `$skip`, `$filter`)
- SSL certificate verification (configurable)

**Requires:**
- Valid access token from `getXAPIToken()`
- Properly formatted endpoint URI
- Consistent parameter structure

---

## 📅 Date & Time Utilities

### `parseIsoDateTime($isoDateTime)`
Comprehensive ISO 8601 parser with localization support.

**Parameters:**
- `$isoDateTime` *(string)*: ISO 8601 formatted datetime string

**Returns:** `array|null` containing:
- Date/time components
- Day names (English/Croatian)
- UTC timezone handling

```php
[
  'date' => 'YYYY-MM-DD',
  'time' => 'HH:MM:SS',
  'dayOfWeekEnglish' => 'Monday',
  'dayOfWeekCroatian' => 'Ponedjeljak'
]
```

**Throws:** `Exception` on invalid datetime formats

**Logic:**
- Extracts date and time components
- Handles UTC timezone conversion
- Provides day names in English and Croatian

**Requires:**
- PHP `intl` extension for Croatian localization
- Valid ISO 8601 input string

---

### `parseIsoDuration($isoDuration)`
Advanced duration parser for ISO 8601 duration strings.

**Parameters:**
- `$isoDuration` *(string)*: ISO 8601 duration string

**Returns:** `array|null` containing:
- Total seconds
- HH:MM:SS duration format
- Human-readable duration string

```php
[
  'seconds' => 3600,
  'hhmmss' => '01:00:00',
  'readable' => 'T01:00:00'
]
```

**Throws:** `Exception` on invalid duration formats

**Logic:**  
- Calculates total seconds from duration components
- Converts to HH:MM:SS format
- Generates human-readable string

**Requires:**
- Valid ISO 8601 duration format (starting with 'P')
- Properly formatted time components

---

## 📊 Data Processing

### Data Flow:
1. `getData()` - Main entry point
2. `invokeXAPIRequest()` - Fetches raw data
3. `expandDataset()` - Adds derived columns
4. `testResponse()` - Validates structure
5. `showSample()` - Displays preview
6. `exportToCSV()`/`exportToExcel()` - Final output

### `expandDataset($data, $endpoint)`
Expands the dataset by parsing datetime and duration fields into additional columns.

**Parameters:**
- `$data` *(array)*: Raw API response data
- `$endpoint` *(string)*: Endpoint identifier

**Returns:** `array` Expanded dataset with:
- Additional date/time components
- Formatted duration fields

**Throws:** `Exception` on:
- Invalid endpoint configuration
- Missing required fields

**Logic:**
- Identifies datetime/duration fields from endpoint config
- Adds parsed components as new columns
- Preserves original data structure

**Requires:**
- Valid `$endpointColumns` configuration
- Properly formatted API response

---

### `prepareExportData($data, $endpoint)`
Prepares headers and normalizes all rows for export, including added columns.

**Parameters:**
- `$data` *(array)*: API response data
- `$endpoint` *(string)*: Endpoint name

**Returns:** `array` containing:
- Complete headers (including derived columns)
- Normalized data rows

```php
[
  'headers' => [...],
  'normalizedData' => [...]
]
```

**Throws:** `Exception` on:
- Invalid data structure
- Missing required columns

**Logic:**
- Merges base and derived columns
- Handles array-to-string conversion
- Normalizes empty values

**Requires:**
- Expanded dataset from `expandDataset()`
- Consistent column definitions

---

## 📁 Export Functions

### Shared Features:
- **UTF-8 BOM Handling**: Ensures proper encoding for Excel compatibility
- **Column Normalization**: Consistent formatting across all data
- **Array Conversion**: Flattens complex structures to strings
- **Format-Specific Optimizations**: Tailored processing for CSV/XLSX

### `exportToCSV($data, $filename, $endpoint)`
Generates CSV exports from normalized data.

**Parameters:**
- `$data` *(array)*: Processed API data
- `$filename` *(string)*: Full output file path
- `$endpoint` *(string)*: Source endpoint identifier

**Returns:** `void` (writes directly to file)

**Throws:** `Exception` on:
- File permission issues
- Invalid data structure
- Write failures

**Logic:**
- Prepares UTF-8 BOM header for Excel compatibility
- Escapes special characters
- Handles line breaks in content
- Uses proper CSV delimiters

**Requires:**
- Data processed by `prepareExportData()`
- Write permissions to target directory

---

### `exportToExcel($data, $filename, $endpoint)`
Generates XLSX exports from normalized data using PhpSpreadsheet.

**Parameters:**
- `$data` *(array)*: Processed API data  
- `$filename` *(string)*: Full output file path
- `$endpoint` *(string)*: Source endpoint identifier

**Returns:** `void` (writes directly to file)

**Throws:** `Exception` on:
- PhpSpreadsheet initialization failures
- Invalid cell data
- File write errors

**Logic:**
- Applies auto-sizing to columns
- Adds header styling
- Handles different data types
- Optimizes memory usage

**Requires:**
- PhpSpreadsheet library (`composer require phpoffice/phpspreadsheet`)
- PHP extensions: zip, xml, gd
- 64MB+ memory for large datasets

> **Note:** Excel exports typically require 2-3x more memory than equivalent CSV exports.

---

## 🧪 Response Validation

### `testResponse($data)`
Validates the structure and content of the API response. Populates warnings if necessary.

**Parameters:**
- `$data` *(array)*: Raw API response data

**Returns:** `void`

**Throws:** `Exception` on:
- Missing required `value` array
- Empty dataset when records expected
- Invalid response structure
- Boolean-only responses without data

**Logic:**
1. **Structure Validation**:
   - Checks for `value` array existence
   - Verifies `@odata.count` matches record count
2. **Content Validation**:
   - Detects empty/boolean-only responses
   - Handles flat object responses differently
   - Validates pagination consistency
3. **Warning Generation**:
   - Records partial dataset warnings
   - Logs response characteristics

**Requires:**
- Properly formatted JSON response
- Consistent OData conventions
- Session for warning storage (`$_SESSION['warnings']`)

---

### `showSample($data, $columns = [])`
Displays a sample of the API data as an HTML table for preview in-browser.

**Parameters:**
- `$data` *(array)*: API response data
- `$columns` *(array)*: Column headers to display

**Returns:** `void` (outputs HTML directly)

**Throws:** `Exception` on:
- Invalid data structures
- Missing required columns

**Logic:**
1. **Format Detection**:
   - Handles both array and object responses
   - Identifies flat vs nested structures
2. **Rendering**:
   - Limits to 20 sample rows
   - Applies HTML escaping
   - Converts nested arrays to JSON strings
3. **Presentation**:
   - Generates sortable tables
   - Highlights header row
   - Preserves original ordering

**Requires:**
- Valid HTML context
- Bootstrap CSS (for optimal styling)
- UTF-8 encoding

> **Security Note:** All user-provided data is properly escaped to prevent XSS vulnerabilities.

---

## 🔁 Data Retrieval

### `getData($endpoint, $from, $to, $queuedn, $top, $skip)`
Main handler for invoking an API endpoint with parameters and returning structured data.

**Parameters:**
- `$endpoint` *(string)*: Target endpoint name
- `$from` *(string)*: Start date (YYYY-MM-DD)
- `$to` *(string)*: End date (YYYY-MM-DD)
- `$queuedn` *(string)*: Queue DN/extension filter
- `$top` *(int)*: Maximum records to return
- `$skip` *(int)*: Records to skip (pagination)

**Returns:** `array` Structured response data or empty array on error

**Throws:** `Exception` on:
- Invalid endpoint configuration
- Date range errors
- Parameter validation failures

**Logic:**
1. **Parameter Processing**:
   - Converts dates to Zulu time when required
   - Handles queue DN placeholder substitution
   - Validates pagination parameters
2. **API Integration**:
   - Builds complete request URI
   - Manages OData query parameters
   - Handles session warnings
3. **Data Flow**:
   - Calls `invokeXAPIRequest()`
   - Processes through validation pipeline
   - Returns normalized structure

**Requires:**
- Valid endpoint in `$endpointConfigs`
- Properly formatted input parameters
- Active API session
---

## 🔧 Configuration

### config.php
**Required Settings:**
- `XAPI_URL` (string) - Base URL of your 3CX server (e.g. `'https://your.3cx.server'`)
- `XAPI_USER` (string) - Client ID for API authentication
- `XAPI_KEY` (string) - Client secret for API authentication
- `SWAGGER_AGE_LIMIT` (int) - Definition refresh interval in seconds (eg. `86400` for 24 hours)

```php
define('XAPI_URL', 'https://your.3cx.server');
define('XAPI_USER', 'your_client_id');
define('XAPI_KEY', 'your_client_secret');
define('SWAGGER_AGE_LIMIT', 86400); // 24 hours
```

**Optional Debug Settings:**
- `XAPI_DEBUG` (bool) - Enables detailed error reporting when `true`
- `DISABLE_SSL_VERIFICATION` (bool) - Disables SSL checks for testing (never use in production)

```php
define('XAPI_DEBUG', true);
define('DISABLE_SSL_VERIFICATION', true);
```

### System Requirements
**PHP Extensions:**
- Required: `curl`, `json`, `intl`, `fileinfo`, `mbstring`
- Recommended: `zip`, `gd` (for Excel exports)

**Dependencies:**
- PhpSpreadsheet (via Composer)
- Node.js + yaml2json (for Swagger processing)

### Dependencies:
- Global arrays: `$endpointConfigs` and `$endpointColumns` from definitions.php
- PHP extensions: `curl`, `json`, `fileinfo`, `intl`, `gd`, `mbstring`, `zip`
- PHP.ini settings: `max_execution_time`, `max_input_time`, `memory_limit`
- Composer: as prerequisite to manage PHP dependencies
- PHP dependencies: `composer require phpoffice/phpspreadsheet`
- 3rd party binaries: Node.js `scoop install nodejs-lts` and yaml2json `npm install -g yamljs`

> ⚠️ Note: All functions rely on these configuration values being properly set.

### Security Settings (built-in defaults)
**Session Protection:**
- **Secure Cookies**: Only transmitted over HTTPS
- **HTTP-Only Flag**: Prevents JavaScript access
- **SameSite Strict**: Blocks cross-site requests
- **Session Lifetime**: 1 hour expiration (3600 seconds)
- **ID Regeneration**: Prevents session fixation

**Data Protection:**
- **Input Sanitization**: All user inputs filtered
- **Output Encoding**: HTML special chars escaped
- **CSRF Protection**: Built into form handling

**API Security:**
- **Token Rotation**: Fresh OAuth tokens per request
- **Credential Storage**: Never logged or cached
- **IP Whitelisting**: Recommended for production

### Security Recommendations
1. **For Production:**
   - Enable SSL verification (`DISABLE_SSL_VERIFICATION=false`)
   - Disable debug mode (`XAPI_DEBUG=false`)
   - Implement IP restrictions on PBX console
   - Rotate API credentials regularly

2. **File Security:**
   - Restrict access to `config.php`
   - Store outside web root if possible
   - Set strict file permissions (read-only for configs)

3. **Session Management:**
   - Use separate session storage
   - Implement idle timeout
   - Destroy sessions after logout

> **Critical:** Never commit actual credentials to version control. Use environment variables or secure vaults for production deployments.
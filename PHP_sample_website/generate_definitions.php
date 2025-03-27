<?php
/**
 * File: generate_definitions.php
 * Purpose: Generates endpoint definitions from Swagger/OpenAPI specification
 * 
 * This script:
 * 1. Converts swagger.yaml to swagger.json if needed
 * 2. Parses the OpenAPI specification
 * 3. Extracts GET endpoints and their parameters
 * 4. Generates PHP configuration files for API endpoints
 * 5. Handles special cases and default values
 * 
 * Output:
 * - Creates definitions.php with endpoint configurations and column definitions
 */

/**
 * AUTO-CONVERSION FROM YAML TO JSON
 * 
 * Converts swagger.yaml to swagger.json when:
 * - swagger.json doesn't exist, OR
 * - swagger.yaml is newer than swagger.json
 * 
 * Requires yaml2json from npm (install with: npm install -g yamljs)
 */
if (!file_exists('swagger.json') || filemtime('swagger.yaml') > filemtime('swagger.json')) {
    shell_exec('yaml2json swagger.yaml > swagger.json');
}

/**
 * Converts OpenAPI type+format to simplified PHP type representation
 * 
 * @param string $type The OpenAPI type (string, integer, boolean, etc.)
 * @param string|null $format The OpenAPI format (date-time, duration, etc.)
 * @return string Simplified type for PHP usage
 */
function convertType($type, $format) {
    if ($format === 'date-time') return 'datetime';
    if ($type === 'boolean') return 'boolean';
    if ($type === 'integer') return 'integer';
    if ($type === 'number') return 'float';
    if ($type === 'string' && $format === 'duration') return 'duration';
    return 'string';
}

/**
 * Formats a PHP array as a nicely formatted file block
 * 
 * Used to generate the definitions.php file with proper formatting
 * 
 * @param string $name The variable name to output
 * @param array $data The array data to format
 * @return string Formatted PHP code block
 */
function exportArrayFormatted($name, $data) {
    $output = "// Array containing " . ($name === 'endpointConfigs' ? 
        'URI definitions for all endpoints (uri, with/or/without function, plus parameters, and datetime format expected).' : 
        'column definitions for all endpoints (name & type).') . "\n";
    $output .= "$" . $name . " = [\n";
    
    foreach ($data as $endpoint => $items) {
        if (is_string($items)) {
            $output .= "    // \"$endpoint\" => $items\n";
            continue;
        }
        
        $output .= "    \"$endpoint\" => [\n";
        foreach ($items as $key => $value) {
            if (is_array($value)) {
                $output .= "        \"$key\" => [\n";
                foreach ($value as $k => $v) {
                    $keyQuote = (str_starts_with($k, '$')) ? "'" : '"';
                    $output .= "            {$keyQuote}{$k}{$keyQuote} => \"$v\",\n";
                }
                $output .= "        ],\n";
            } else {
                $output .= "        \"$key\" => \"$value\",\n";
            }
        }
        $output .= "    ],\n";
    }
    $output .= "];\n\n";

    return $output;
}

/**
 * Main logic: reads the Swagger JSON and extracts useful GET endpoints
 * 
 * Processes the OpenAPI specification to:
 * - Identify valid GET endpoints
 * - Extract parameter information
 * - Determine response schemas
 * - Handle special cases
 * 
 * @param array $swagger Parsed OpenAPI specification
 * @return array Contains 'endpointConfigs' and 'endpointColumns'
 */
function getEndpointConfigsAndColumns($swagger) {
    $configs = []; // Stores endpoint configurations
    $columns = []; // Stores column definitions

    // Extract relevant parts from OpenAPI spec
    $paths = $swagger['paths'] ?? [];
    $schemas = $swagger['components']['schemas'] ?? [];
    $responses = $swagger['components']['responses'] ?? [];

    // Process each path and method in the specification
    foreach ($paths as $path => $methods) {
        foreach ($methods as $method => $details) {
            // Skip non-GET methods
            if (strtolower($method) !== 'get') continue;
            
            // Skip if no tag is defined (unlikely in proper OpenAPI specs)
            if (!isset($details['tags'][0])) continue;

            $tag = $details['tags'][0];
            $operationId = $details['operationId'] ?? uniqid();
            $endpoint = $tag;
            
            // Ensure endpoint name uniqueness
            if (isset($configs[$endpoint])) {
                $endpoint = "$tag/$operationId";
            }

            /**
             * KNOWN ENDPOINT EXCLUSIONS
             * 
             * Skip endpoints that match certain patterns:
             * - My-prefixed endpoints (e.g., MyUser, MyGroup, MyToken)
             * - Download endpoints
             * - Single-parameter function calls
             * - Single-resource endpoints using path({Id})
             */
            if (preg_match('#/My[A-Z]#', $path)) {
                $configs["$endpoint/$operationId"] = 'disabled: My-prefixed endpoint (e.g. MyUser, MyToken)';
                continue;
            }
            if (preg_match('#/Pbx\\.Download#', $path)) {
                $configs["$endpoint/$operationId"] = 'disabled: Download endpoint';
                continue;
            }
            if (preg_match('#/Pbx\\.[^(]+\\(([^,]+)\\)#', $path)) {
                $configs["$endpoint/$operationId"] = 'disabled: Single-param function call';
                continue;
            }
            if (preg_match('/\\(\\{.*?}/', $path)) {
                $configs["$endpoint/$operationId"] = 'disabled: Single-resource endpoint using path({Id})';
                continue;
            }

            // Collect allowed query parameters
            $allowedQueryParams = [];
            if (isset($details['parameters']) && is_array($details['parameters'])) {
                foreach ($details['parameters'] as $param) {
                    if (($param['in'] ?? '') === 'query' && isset($param['name'])) {
                        $name = $param['name'];
                        if (in_array($name, ['$filter', '$count', '$top', '$skip'])) {
                            $allowedQueryParams[$name] = true;
                        }
                    }
                }
            }

            /**
             * FORCE ODATA PARAMETERS FOR SPECIFIC TAGS
             * 
             * Some endpoints support OData parameters ($count, $top, and $skip) even if not documented
             * in the OpenAPI spec. We force-add them for known endpoints.
             */
            $forceOData = ['ActiveCalls', 'CallHistoryView'];
            if (in_array($tag, $forceOData)) {
                foreach (['$count', '$top', '$skip'] as $odataParam) {
                    if (!isset($allowedQueryParams[$odataParam])) {
                        $allowedQueryParams[$odataParam] = true;
                    }
                }
            }

            // Resolve the response schema through references if needed
            $response = $details['responses']['200'] ?? null;
            $schema = null;
            $itemRef = null;

            // Handle $ref in response
            if (isset($response['$ref'])) {
                $responseKey = basename($response['$ref']);
                $responseDef = $responses[$responseKey] ?? null;
                if (isset($responseDef['content']['application/json']['schema'])) {
                    $schema = $responseDef['content']['application/json']['schema'];
                    if (isset($schema['$ref'])) {
                        $schemaKey = basename($schema['$ref']);
                        $schema = $schemas[$schemaKey] ?? null;
                    }
                }
            }

            // Direct response schema fallback
            if (!$schema && isset($response['content']['application/json']['schema'])) {
                $schema = $response['content']['application/json']['schema'];
                if (isset($schema['$ref'])) {
                    $schemaKey = basename($schema['$ref']);
                    $schema = $schemas[$schemaKey] ?? null;
                }
            }

            // Handle allOf schema composition (common in OpenAPI, usually wrapped collections)
            if (isset($schema['allOf'])) {
                foreach ($schema['allOf'] as $part) {
                    if (isset($part['properties']['value']['items']['$ref'])) {
                        $itemRef = $part['properties']['value']['items']['$ref'];
                        break;
                    }
                }
            }

            // Process flat inline schemas (direct property definitions)
            if (!$itemRef && isset($schema['properties']) && is_array($schema['properties'])) {
                $propTypes = [];
                foreach ($schema['properties'] as $prop => $meta) {
                    $type = convertType($meta['type'] ?? 'string', $meta['format'] ?? null);
                    $propTypes[$prop] = $type;
                }
                
                if (!empty($propTypes)) {
                    $columns[$endpoint] = $propTypes;
                    
                    // Determine default order field (first datetime field or first field)
                    $orderField = array_key_first($propTypes);
                    foreach ($propTypes as $name => $type) {
                        if ($type === 'datetime') {
                            $orderField = $name;
                            break;
                        }
                    }
                    
                    // Build parameter configuration
                    $params = [];
                    if (isset($allowedQueryParams['$count'])) $params['$count'] = 'true';
                    if (isset($allowedQueryParams['$skip'])) $params['$skip'] = '{skip}';
                    if (isset($allowedQueryParams['$top'])) $params['$top'] = '{top}';
                    
                    // Check if endpoint uses Zulu time format
                    $isZulu = preg_match('/\b(startDate|endDate|periodFrom|periodTo|startDt|endDt|chartDate|Timestamp)\b/i', $path);
                    
                    $configs[$endpoint] = [
                        'url' => "/xapi/v1$path",
                        'params' => $params,
                        'zulu' => $isZulu ? true : false
                    ];
                }
                continue;
            }

            // Process collection-style responses with referenced schemas
            if ($itemRef) {
                $itemSchemaKey = basename($itemRef);
                $itemSchema = $schemas[$itemSchemaKey] ?? null;
                if (!$itemSchema || !isset($itemSchema['properties'])) continue;
                
                $propTypes = [];
                foreach ($itemSchema['properties'] as $prop => $meta) {
                    $type = convertType($meta['type'] ?? 'string', $meta['format'] ?? null);
                    $propTypes[$prop] = $type;
                }
                
                if (!empty($propTypes)) {
                    $columns[$endpoint] = $propTypes;
                    
                    // Determine default order field
                    $orderField = array_key_first($propTypes);
                    foreach ($propTypes as $name => $type) {
                        if ($type === 'datetime') {
                            $orderField = $name;
                            break;
                        }
                    }
                    
                    // Build $filter and other parameters
                    $params = [];
                    $dateFields = ['Timestamp', 'StartTime', 'SegmentStartTime', 'TimeGenerated', 'CallTime'];
                    $hasFilterSupport = isset($allowedQueryParams['$filter']) || in_array($tag, $forceOData);
                    
                    // Set up date filtering if supported
                    foreach ($dateFields as $df) {
                        if (array_key_exists($df, $propTypes) && $hasFilterSupport) {
                            $params['$filter'] = "date($df) ge {from} and date($df) le {to}";
                            break;
                        }
                    }
                    
                    // Add other OData parameters
                    if (isset($allowedQueryParams['$count'])) $params['$count'] = 'true';
                    if (isset($allowedQueryParams['$skip'])) $params['$skip'] = '{skip}';
                    if (isset($allowedQueryParams['$top'])) $params['$top'] = '{top}';
                    
                    // Check for Zulu time format usage
                    $isZulu = preg_match('/\b(startDate|endDate|periodFrom|periodTo|startDt|endDt|chartDate|Timestamp)\b/i', $path);
                    
                    $configs[$endpoint] = [
                        'url' => "/xapi/v1$path",
                        'params' => $params,
                        'zulu' => $isZulu ? true : false
                    ];
                }
            }
        }
    }

    // Sort output for consistency and easier diffing
    ksort($configs);
    ksort($columns);

    return ['endpointConfigs' => $configs, 'endpointColumns' => $columns];
}

// === MAIN EXECUTION ===

// Load and parse the OpenAPI specification
$swagger = json_decode(file_get_contents('swagger.json'), true);
$result = getEndpointConfigsAndColumns($swagger);

// Write to definitions.php file in segments
file_put_contents('definitions.php', "<?php\n\n");
file_put_contents('definitions.php', exportArrayFormatted('endpointConfigs', $result['endpointConfigs']), FILE_APPEND);
file_put_contents('definitions.php', exportArrayFormatted('endpointColumns', $result['endpointColumns']), FILE_APPEND);
file_put_contents('definitions.php', "?>\n", FILE_APPEND);

// === POST PROCESSING ===

// Read back the generated file for additional processing
$content = file_get_contents('definitions.php');

/**
 * NORMALIZE PARAMETER VALUES
 * 
 * Replace various parameter placeholders with:
 * - Default values
 * - Standardized names
 * - Proper formatting
 */
$content = str_replace('periodFrom={periodFrom}', 'periodFrom={fromZulu}', $content);
$content = str_replace('periodTo={periodTo}', 'periodTo={toZulu}', $content);
$content = str_replace('startDt={startDt}', 'startDt={fromZulu}', $content);
$content = str_replace('endDt={endDt}', 'endDt={toZulu}', $content);
$content = str_replace('startDate={startDate}', 'startDate={fromZulu}', $content);
$content = str_replace('endDate={endDate}', 'endDate={toZulu}', $content);
$content = str_replace('extension={extension}', "extension=''", $content);
$content = str_replace('call={call}', "call=''", $content);
$content = str_replace('search={search}', "search=''", $content);
$content = str_replace('severity={severity}', "severity='All'", $content);
$content = str_replace('top={top}', 'top=1000', $content);
$content = str_replace('skip={skip}', 'skip=0', $content);

// Replace known DN placeholders with standardized queue DN parameter
$content = str_replace('queueDns={queueDns}', "queueDns='{queuedn}'", $content);
$content = str_replace('queueDnStr={queueDnStr}', "queueDnStr='{queuedn}'", $content);
$content = str_replace('ringGroupDns={ringGroupDns}', "ringGroupDns='{queuedn}'", $content);
$content = str_replace('agentDnStr={agentDnStr}', "agentDnStr='{queuedn}'", $content);

// Replace common defaults for various parameters
$content = str_replace('waitInterval={waitInterval}', "waitInterval='0:00:0'", $content);
$content = str_replace('answerInterval={answerInterval}', "answerInterval='0:00:0'", $content);
$content = str_replace('hidePcalls={hidePcalls}', 'hidePcalls=false', $content);
$content = str_replace('sourceFilter={sourceFilter}', "sourceFilter=''", $content);
$content = str_replace('destinationFilter={destinationFilter}', "destinationFilter=''", $content);
$content = str_replace('sourceType={sourceType}', 'sourceType=0', $content);
$content = str_replace('destinationType={destinationType}', 'destinationType=0', $content);
$content = str_replace('callsType={callsType}', 'callsType=0', $content);
$content = str_replace('callTimeFilterType={callTimeFilterType}', 'callTimeFilterType=0', $content);
$content = str_replace('callTimeFilterFrom={callTimeFilterFrom}', "callTimeFilterFrom='0:00:0'", $content);
$content = str_replace('callTimeFilterTo={callTimeFilterTo}', "callTimeFilterTo='0:00:0'", $content);
$content = str_replace('groupNumber={groupNumber}', "groupNumber='GRP0000'", $content);
$content = str_replace('callArea={callArea}', 'callArea=0', $content);
$content = str_replace('{groupFilter}', "'GRP0000'", $content);
$content = str_replace('{callClass}', '0', $content);
$content = str_replace('{participantType}', '0', $content);
$content = str_replace('{grantPeriodDays}', '30', $content);

// Placeholders that require manual user override (marked with 'changethis')
$content = str_replace('{extensionFilter}', "''", $content);
$content = str_replace('{chartBy}', "''", $content);
$content = str_replace('chartDate={chartDate}', 'chartDate={fromZulu}', $content);
$content = str_replace('{clientTimeZone}', "'Etc/GMT'", $content);
$content = str_replace('{includeInternalCalls}', 'false', $content);
$content = str_replace('{includeQueueCalls}', 'false', $content);
$content = str_replace('{groupStr}', "''", $content);
$content = str_replace('{resellerId}', "'changethis'", $content);
$content = str_replace('{name}', "'changethis'", $content);
$content = str_replace('{dnNumber}', "'{queuedn}'", $content);
$content = str_replace('{number}', "'{queuedn}'", $content);
$content = str_replace('{guid}', "'changethis'", $content); // string, required ; '/ConferenceSettings/Pbx.GetMCURow(guid={guid})':
$content = str_replace('{mac}', "'changethis'", $content); // string, required ; '/Users/Pbx.GetPhoneRegistrar(mac={mac})':
$content = str_replace('{fileName}', "'changethis'", $content);
$content = str_replace('{userId}', "'changethis'", $content); // integer, required ; '/Users/Pbx.DownloadGreeting(userId={userId},fileName={fileName})':
$content = str_replace('{template}', "'changethis'", $content); // string, required ; '/Trunks/Pbx.InitTrunk(template={template})':

// Convert zulu format flags from string to proper boolean
$content = str_replace('"zulu" => "1",', "'zulu' => true,", $content);
$content = preg_replace('/"zulu" => \"?(?:0)?\"?,/', "'zulu' => false,", $content);

// Write final output with UTF-8 BOM
file_put_contents('definitions.php', "\xEF\xBB\xBF" . $content);

?>
# 3CX-XAPI_examples
Example scripts and code to work with 3CX V20 XAPI endpoints
  
# 2025-03-12
- First upload!
- Includes working scripts for `/xapi/v1/CallHistoryView` and `/xapi/v1/ReportCallLogData/Pbx.GetCallLogData()` endpoints
- Developed with the help of 3CX community! Thanks everyone! (links below to some helpful threads!)
- Aimed at 3CX V20 XAPI
  
Scripts are well commented and well layed out (IMHO).  
  
Simply executing the .ps1 scripts will provide an error notice :  
`Error: Please provide the API key using '-key' parameter. To see complete help use '-help'.`
  
Rest of the usage is explained in help section, such as (will differ between scripts):  
```
USAGE:
    \<script_path>\fetch_call_history.ps1 -user "test" -key "your_client_secret" -url "https://YourSubdomainHere.3cx.eu:5001" -from "YYYY-MM-DD" -to "YYYY-MM-DD" -top 100000

EXAMPLES:
    \<script_path>\fetch_call_history.ps1 -user "test" -key "abc123" -url "https://example.3cx.eu:5001" -from "2025-02-01" -to "2025-02-28" -top 50000
    \<script_path>\fetch_call_history.ps1 -user "admin" -key "xyz456" -url "https://yourpbx.3cx.eu:5001" -from "2024-12-01" -to "2024-12-31" -top 200000

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
- Running command with default parameters will use:
        -user "test" -url "https://YourSubdomainHere.3cx.eu:5001" -from "2025-02-01" -to "2025-02-28" -top 100000
```
  
Current files:  
- fetch_call_history.ps1 -> first script, using `CallHistoryView`, and no progress bar for HTTP request
- fetch_call_history2.ps1 -> same as first but improved with approximation of a progress for HTTP request
- fetch_call_report.ps1 -> variation of the script using `ReportCallLogData` endpoint that provides way more details than just the call logs in first two scripts
  
Scripts were written to be universal, with one minor exception. Due to my own needs I've added names of days in Croatian language in the 3rd script and they're displayed in the last column. It also includes English names of days in column before that. Feel free to ignore or comment out that code, or reuse ut for other languages that you may need. Other than that scripts should be well suited for any user.  
  
Note that scripts require API integration user & key (secret), process of obtaiing one through 3CX Web UI console is explained below.  
  
# Obtaining API credentials
  
You may use either username/password or API client/secret when using XAPI, but this script uses API client/secret.
  
To create new 3CX API client ID and its key/secret do the following:  
  
1) Login with system owner account to your 3CX Web UI / web console
2) Click Admin (bottom left corner)
3) Under: Integrations -> API -> click "+ Add"
4) Enter "Client ID" e.g. "test", set Department to "DEFAULT" and Role to "System Owner"
5) Save, you will get a new pop-up window, click the Copy icon and save your API key/secret somewhere safe, and confirm with OK
6) Tripple check that your API integration was saved as system OWNER because system ADMIN will NOT WORK FOR CALL HISTORY VIEW!
  
You will be using these credentials as `-key` and `-user` when calling the scripts. You can hardcode them inside script if you wish, though keep in mind that allows access to your whole PBX system to anyone that has that script (hardcoded credentials).  
  
Note: During creation process, or later when editing, you should see checkboxes to separately enable `XAPI` and/or `Call Control`. Feel free to check both, but my scripts and examples are related to XAPI, so make sure that's enabled. I've added Call Control API as a short mention at the end of this file.  
  
# Basics on connecting and querying
While scripts in this repo contain full code, everyone likes to start small. So let's walk through some of my own early sample code right here.  
Remember you need API client id and key/secret before proceeding, and make sure you can access the web console from the device you're running this, because your installation may have security in place blocking web (and XAPI) requests from reaching your 3CX system. This can be firewall, network routing, or even white/black listing IPs in the 3CX settings themselves (eg `Admin -> Advanced -> Console Restrictions`). Check that before pulling your hair out about why the code doesn't work! P.S. I've learned the hard way :-)  
  
```
$postParams = @{client_id='yourClientIdGoesHere';client_secret='SomELoNgFrEaKinGStRinGRighTHeRe';grant_type='client_credentials'}
Invoke-WebRequest -Uri https://yourpbxdomain.3cx.eu:5001/connect/token -Method POST -Body $postParams
```
  
Please:
- replace `yourClientIdGoesHere` with Client ID from step 4) of Obtaining API credentials
- replace `SomELoNgFrEaKinGStRinGRighTHeRe` with key/secret displayed to you in step 5) of Obtaining API credentials
- replace `yourpbxdomain.3cx.eu:5001` with FQDN:port of your 3CX web console where you've logged into in step 1) of Obtaining API credentials
  
Reply to this web request should be something like this:
  
```
StatusCode        : 200
StatusDescription : OK
Content           : {"token_type":"Bearer","expires_in":60,"access_token":"eyJhbGciOiJFUzI1NiIsImtpZCI6InZYNllXVnJOZXhpV1BOeEF4ZGJjQUEiL...
RawContent        : HTTP/1.1 200 OK
                    Transfer-Encoding: chunked
                    Connection: keep-alive
                    X-Frame-Options: DENY
                    X-Content-Type-Options: nosniff
                    X-XSS-Protection: 0
                    Content-Security-Policy: default-src 'self'; script-sr...
Forms             : {}
Headers           : {[Transfer-Encoding, chunked], [Connection, keep-alive], [X-Frame-Options, DENY], [X-Content-Type-Options, nosniff]...}
Images            : {}
InputFields       : {}
Links             : {}
ParsedHtml        : mshtml.HTMLDocumentClass
RawContentLength  : 570
```
  
Congratulations, you got the token! Still need to filter it out, but you can see your API token in the `Content`, as `access_token`.  
You can use that for 60 minutes in Postman or with PowerShell to authenticate your following requests to any of the endpoints. Note that Client ID you used needs to be system OWNER to work with some endpoints, while system ADMIN will be enough for others. At the moment I recommend using system OWNER so you don't get stuck due to permissions.  
  
If you capture that `access_token` string to variable `$token` you can then create authorization headers and make a simple web request like this:  
  
```
$headers = @{Authorization="Bearer $token"}
Invoke-RestMethod -Method Get -Uri "https://yourpbxdomain.3cx.eu:5001/xapi/v1/Defs" -Headers $headers
```
  
This endpoint should work with both OWNER and ADMIN rights so it's good way to test the connectivity.  
  
Ready for next step? Let's say you don't want to hardcode your Client ID and secret in code, so you can ask for it using PowerShell `Get-Credential` commandlet, then continue to parse out the token and use it to invoke a REST request:  
  
```
$credentials = Get-Credential
$user = $credentials.UserName
$key = $credentials.GetNetworkCredential().Password
$postParams = @{client_id=$user;client_secret=$key;grant_type='client_credentials'}
$request = Invoke-WebRequest -Uri https://yourpbxdomain.3cx.eu:5001/connect/token -Method POST -Body $postParams
$content = $request.Content| ConvertFrom-Json
$token = $content.access_token
$token
$headers = @{Authorization="Bearer $token"}
Invoke-RestMethod -Method Get -Uri "https://yourpbxdomain.3cx.eu:5001/xapi/v1/ActiveCalls" -Headers $headers | Select-Object -ExpandProperty value | ft
# OR
$activecalls = Invoke-RestMethod -Method Get -Uri "https://yourpbxdomain.3cx.eu:5001/xapi/v1/ActiveCalls" -Headers $headers
$activecalls | Select-Object -ExpandProperty value | Select Caller, Callee, EstablishedAt, ServerNow | ft
# OR
$eventlogs = Invoke-RestMethod -Method Get -Uri "https://yourpbxdomain.3cx.eu:5001/xapi/v1/EventLogs" -Headers $headers
$eventlogs | Select-Object -ExpandProperty value | ft
```
Note that PBX URL is still hardcoded so swap that for your actual FQDN:port combination.  
    
Hopefully this explains the basics of how to create API integration credentials, using them to get the access token, then use that access token to query and endpoint, and show some actual data.  
  
I will just mention this here, as I've tried it, but that's as far as I've used it, if you'd still want to authenticate with simple username and password, you would change the code where you get access token, after that stuff plays out the same. This is some code I've used for literally few minutes to confirm user/pass works.  
  
```
$credentials = Get-Credential
$user = $credentials.UserName
$pass = $credentials.GetNetworkCredential().Password
$postParams = @{Username=$user;SecurityCode = '';Password=$pass}
$jsonParams = $postParams | ConvertTo-Json
$request = Invoke-WebRequest -Uri https://yourpbxdomain.3cx.eu:5001/webclient/api/Login/GetAccessToken -Method 'POST' -ContentType 'application/json' -Body $jsonParams
$content = $request.Content| ConvertFrom-Json
$token1 = $content.Token
$token = $token1.access_token
$token
$headers = @{Authorization="Bearer $token"}
```
  
Base differences are in POST parameters being `@{Username=$user;SecurityCode = '';Password=$pass}` and you send them to different URL with `-Uri https://yourpbxdomain.3cx.eu:5001/webclient/api/Login/GetAccessToken`.  
Note that POST parameters in original case are `@{client_id=$user;client_secret=$key;grant_type='client_credentials'}` and URI is `-Uri https://yourpbxdomain.3cx.eu:5001/connect/token`.  
You CAN NOT mix wrong credential type with wrong URI as you won't get authenticated!  
  
# Simpler example for endpoint that's a function()  
While scripts already contain access to one such endpoint `/xapi/v1/ReportCallLogData/Pbx.GetCallLogData()` I feel that rest of the code may obscure the general way of handling such endpoints.  
  
That's why I'm including this (WAY!) shorter example code:  
  
```
# Set parameters for the request
$from = "2024-12-01T00:00:00Z"
$to = "2024-12-31T23:59:59Z"
$orderBy = "SegmentId"
$orderDir = "desc"
$top = 100
$skip = 0

# Create the query string based on parameters
$query = @(
    "periodFrom=$from",
    "periodTo=$to",
    "sourceType=0",
    "sourceFilter=''",
    "destinationType=0",
    "destinationFilter=''",
    "callsType=0",
    "callTimeFilterType=0",
    "callTimeFilterFrom='0:00:0'",
    "callTimeFilterTo='0:00:0'",
    "hidePcalls=true"
)

# Join query parameters into a single string
$params = $query -join ','

# Define the full URI with query parameters
$FullURI = "https://yourpbxdomain.3cx.eu:5001/xapi/v1/ReportCallLogData/Pbx.GetCallLogData($params)?`$top=$top&`$skip=$skip&`$orderby=$orderBy $orderDir"

# Set headers, including the authorization token
$headers = @{ Authorization = "Bearer $token" }

Write-Host "We will now access this endpoint URI : `n`t Invoke-RestMethod -Method Get -Uri $FullURI -Headers $headers"

# Perform the GET request
$response = Invoke-RestMethod -Method Get -Uri $FullURI -Headers $headers

# Display first 10 rows of the returned output
$response.value | Select-Object -First 10 | ft
```
  
You still need the piece of earlier code to get access token, but if you combine that with this code, and obviously input your own FQDN:port, you should get the data.  
I've included a printout of `We will now access this endpoint URI : ...` so you can see the full URI and how it looks. Skipping anything inside brackets `(...)` will result in 404 error, inputing wrong date format will end up with 500 error, and so on, plenty of places to make mistakes.  
Sadly, documentation is lacking, so for some stuff you'll just need to try and learn from your mistakes. So start with simple but working code, then change parameters one by one, with runs to confirm code still works in between the changes. If you go big, you'll probably fail big as well.  
  
# Error codes (HTTP)  
I want to dedicate this part to some of the issues you'll probably encounter, and what's the most probable issue.  
You will often get codes like 401, 403, 404, 500, 504, maybe more.  
- 401 Unauthorized - meaning you didn't pass the token, passed invalid token, or it simply expired
- 403 Forbidden - most of the time it was due to differences of permissions between system owner and system admin
- 404 Not Found - while it may mean you've entered wrong URL or made a type in domain, there is one more big one, if you use function() type endpoints, not providing all required data, or using malformed data, you may get 404 error because whatever you typed inside brackets `(...)` does not respond to expected data, so if your URL looks good, and you're using endpoint that contains brackets `(...)`, check the stuff inside brackets as well
- 500 Internal Server Error - obviously, some big unknown went wrong, just to name a few, wrong data type was sent (eg you sent string when XAPI expected integer), data was malformed (eg. wrong date/time format), and so on
- 504 Gateway Timeout - long running query timed out, you may encounter that if you pull a huge dataset from CallHistoryView for example, solution is usually to select shorter time range as an easy way to make data set smaller and easier to process
  
# Official documentation  
URL: https://www.3cx.com/docs/configuration-rest-api/  
This page covers basics of authentication using `/connect/token endpoint` while also leading you to the following links...  
  
URL: https://www.3cx.com/docs/configuration-rest-api-endpoints/  
This page covers SOME of the endpoints available through XAPI. Currently lists token authentication, Users, Groups, Departments and Parking. Which is roughly... 5-10% of functionality available through XAPI.  
Page is currently listed as updated on Nov 6th 2024, so hopefully they will eventually get to updating it with more examples.  
  
URL: https://github.com/3cx/xapi-tutorial  
This is named "XAPI Tutorial" but it's more of a TypeScript sample code. At least it was updated more recently (a month or less), and contains a really important source of further information:  
swagger.yaml : https://github.com/3cx/xapi-tutorial/blob/master/swagger.yaml  
  
Swagger file is available on your own PBX as well, but you need to know how to access it, so for first time users this here is sort of a gold mine compared to other official (and unofficial) information available at the moment.  
  
For the reference your local swagger should be located at URL: `https://yourpbxdomain.3cx.eu:5001/xapi/v1/swagger.yaml`  
You can also see some of the information by running command: `Invoke-RestMethod -Method Get -Uri "https://yourpbxdomain.3cx.eu:5001/xapi/v1" -Headers $headers | Select-Object -ExpandProperty value`  
  
# Postman / Swagger specs  
Luckily, we have two nice resources to visualize `swagger.yaml`:
- Go to https://editor-next.swagger.io/ and from menu pick `File - Import URL` and paste that same `swagger.yaml` URL from GitHub : `https://github.com/3cx/xapi-tutorial/blob/master/swagger.yaml `, and you can now browse it in more human readable format
- Someone also put whole XAPI spec on Postman website, at https://www.postman.com/simsyn-dev/dev/collection/rubys7v/xapi , which is another good way to browse it and learn about it with a bit more visual presentation.  
  
For example digging into CallHistoryView, you can see a download function endpoint, but also a normal entity endpoint to query data, you can then see query parameters like `$top,$filter,$count,$orderby,$select`, their data types, and so on. You also get `curl` examples, and if you dig into "Responses" (in SwaggerEditor) or "Retrieved collection" (in Postman) you can see expected output in JSON, again with the structure, value names and data types, and so on. Now you really get the feeling what to expect and what's available. Use one you prefer, as much as I see they output same data with slightly different representation, that's all.  
  
# OData protocol specifications  
URL: https://docs.oasis-open.org/odata/odata/v4.0/errata03/os/complete/part1-protocol/odata-v4.0-errata03-os-part1-protocol-complete.html#_The_$filter_System  
Another gold mine, at least for those that haven't yet used OData. I'm linking directly to the `$filter` section as it describes supported operators and built-in functions, as I got stuck there for a while myself and I believe it is really helpful to people new to OData protocol. Just in case you didn't get it, 3CX XAPI uses this specification, so - must read!  
  
# 3CX Community Forum  
3CX paying customers should have access to official community forums. Everyone else can still read the content.  
If you have access login here: https://www.3cx.com/community/  
  
Some useful threads:  
- https://www.3cx.com/community/threads/api-callhistoryview-filter-datetime-parameters.132426/
* Discussing issues accessing `CallHistoryView` endpoint and filtering by the date/time as defined with ISO specification
- https://www.3cx.com/community/threads/3cx-xapi-callhistoryview-code-explanations.132684/
* Discussion about codes present in outputs of both `CallHistoryView` and `ReportCallLogData` endpoints
- https://www.3cx.com/community/threads/3cx-v20-api.132178/
* Has some connection examples in Python and links to other threads/posts with PowerShell examples
- https://www.3cx.com/community/threads/help-getting-the-api-token-on-v20-build-1620.125285/#post-591067
- https://www.3cx.com/community/threads/how-to-use-3cx-api.131540/#post-626176
* Talks about how to use `/ReportCallLogData/Pbx.GetCallLogData()` because it is a function() so syntax and requirements are different
- https://www.3cx.com/community/threads/setup-of-call-control-api.131572/
* Sort of a warning to pitfals represented by somewhat poor and undocumented aspects of UI on the web console while creating API integration credentials
  
# 3rd party PowerShell module for 3CX XAPI  
I've found a PS module that looks functional, though it covers basic endpoint. It did not suite my purposes, but I am including it here for the reference, perhaps it keeps getting updates and maybe grows into something more useful over time. Important note is that this wrapper module uses username and password for authentication and authorization! Your API client ID/secret will be useless unless you modify the module code!!  
  
URL: https://github.com/O-IT/3CX  
Installation:  
```
Install-Module -Name 3CX
Import-Module -Name 3CX
```
  
# 3rd party Powershell module for Excel  
This one is pretty popular, and while not in any way related to 3CX, it makes it easier to export data to XLSX, format columns, and similar, so that you get finished XLSX file after running PS script.  
  
URL: https://github.com/dfinke/ImportExcel  
Installation:  
```
Install-Module ImportExcel
Import-Module ImportExcel
```
  
# 3CX Call Control API  
I want to be clear that I did NOT USE and DO NOT PLAN to use this API. Documentation was updated yesterday so it should be OK. I am providing links here for the sake of completeness.  
  
URLs:  
- https://www.3cx.com/docs/call-control-api/
- https://www.3cx.com/docs/call-control-api-endpoints
  
Note that Configuration XAPI, and Call Controll API are NOT the same thing, even though they may share some similarities!  
Despite this, you should feel free to try out variations of code related to Configuration XAPI on the Call Control API, as basic workflow should be the same (access token, and such).  
You can easily differentiate the two by their endpoint URLs, XAPI uses `https://<FQDN:port>/xapi/v1/` while Call Control uses `https://<FQDN:port>/callcontrol/`, both URIs literally contain the name of relevant API (`xapi` vs `callcontrol`).  
Also, remember that you need to specifically enable if your API integration client ID (credentials) are to be used with one, the other, or both APIs.  
    
# Future content  
I plan to make a PHP sample, at least for basic token retrieval and calling few simpler endpoints, but don't have strict timeline yet.  
If you have something useful to add let me know, I'd be glad to add it.  
  
Note once more that the API is relatively new, and there isn't much material about it. Official docs are lacking at best... so even these few samples required a lot if trials and errors. Hopefully this repo with this Readme and a few samples helps people get started and gets the ball rolling. 3CX Version 20, Update 5 was just released a day ago, and they are promissing more reporting and API news for Update 6 (probably early summer 2025) so things will most probably change a lot during 2025. Keep watching official changelogs for any news : https://www.3cx.com/blog/change-log/phone-system-change-log-v20/ ; as well as forum and blogs for news about what they call Reporting 2.0 : https://www.3cx.com/community/threads/reporting-2-0-the-reporting-roadmap-at-3cx.131057/

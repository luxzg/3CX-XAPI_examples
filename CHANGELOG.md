# Changelog of this repository

# 2025-03-18
First public release of proper 3CX_XAPI_Module v0.1.0.  
Many changes introduced:  
- added headers to all files adding file name, URL to this github repo, author, short excerpt for endpoint format, etc
- support for PS7.5+ added:
	- removed old `Confirm-PowerShellModuleVersion` that prevented anything over 5.1 to run, and replaced it with `Test-PowerShellModuleVersion` with added functionality
 	- added `$pscheck` variable to function `Invoke-XAPIRequestWithProgress` together with expanded try/catch if/else based on `$pscheck` to separate code paths for 5.1 and 7.5+
  	- using `DateKind` on JSON conversion to fix auto-formatting of dates on PS7.5+
  	- added fix for UTF-8 encoding when PS7.5+
  	- added forced script exit if `Invoke-XAPIRequestWithProgress` fails
- propper module support:
	- while I was halfway there few days ago, with .psm1 files, scripts were just scripts that loaded couple modules...
 	- now whole thing is one big module `3CX_XAPI_Module`
 	- all scripts are now functions of this new parent module
  	- added `3CX_XAPI_Module.psm1` and `3CX_XAPI_Module.psd1` that make the module alive
  	- removed `Import-Module` lines from scripts as they are loaded by parent module
  	- all new functions exported as module members
  	- changed `Get-ScriptPaths` to `Get-ExportPaths` with simplified structure, as now it's only needed to generate CSV/XLSX paths
  	- reworked all `exit` (and similar) lines to `throw` to prevent module closing console
  	- at the same time checked and updated all exit/error/warning/throw messages, also added few more comments, making everything nicer overall
 - new help:
 	- since it is now a module I've decided to dig into module help
  	- removed all `-help` parameters from scripts/functions
   	- removed `Show-HelpNotes` function from module with common functions
   	- created new help file `about_3CX_XAPI_Module.help.txt` describing module itself
   	- created helper function `Get-3CXHelp` to better expose help topics and commands
   	- created new XML file `3CX_XAPI_Module-help.xml` that contains all help text previously held by .ps1 & .psm1 files
   	- improved descriptions, parameter definitions, examples, etc.
 - new endpoints:
 	- added `ActiveCalls` script/function as a simple example (no file exports, no date/time conversions, real simple!)
 - smaller fixes:
 	- made all `queueDns` parameters lowercase for consistency
Note: This is my first try at PS module, so keep that in mind!  
  
Module usage:  
- download this repo as ZIP, extract to local path of your liking
- open Powershell 5.1 or PowerShell 7.5+
- go to directory `C:\<yourpath...>\3CX_XAPI_Module`
- import module by running: `Import-Module .\3CX_XAPI_Module -Verbose`
- get list of commands by running: `Get-Command -Module 3CX_XAPI_Module`
- get general module help by running: `Get-3CXHelp`
- get help on commands by running for example: `Get-Help Get-ActiveCalls -Examples` or `Get-Help Get-CallHistoryView -Detailed`
- run commands to access XAPI for example:
```
Get-ActiveCalls -user "testuser" -key "AbCdEfGhIjKlMnOpRsTuVz1234567890" -url "https://yourpbxurl.3cx.eu:5001" -skip 0 -top 100
Get-CallHistoryView -user "testuser" -key "AbCdEfGhIjKlMnOpRsTuVz1234567890" -url "https://yourpbxurl.3cx.eu:5001" -from "2025-03-01" -to "2025-03-15" -skip 0 -top 100
Get-ReportAbandonedQueueCalls -user "testuser" -key "AbCdEfGhIjKlMnOpRsTuVz1234567890" -url "https://yourpbxurl.3cx.eu:5001" -from "2025-03-01T00:00:00Z" -to "2025-03-15T23:59:59Z" -skip 0 -top 100 -queuedns 1111
Get-ReportCallLogData -user "testuser" -key "AbCdEfGhIjKlMnOpRsTuVz1234567890" -url "https://yourpbxurl.3cx.eu:5001" -from "2025-03-01T00:00:00Z" -to "2025-03-15T23:59:59Z" -skip 0 -top 100
Get-ReportQueuePerformanceOverview -user "testuser" -key "AbCdEfGhIjKlMnOpRsTuVz1234567890" -url "https://yourpbxurl.3cx.eu:5001" -from "2025-03-01T00:00:00Z" -to "2025-03-15T23:59:59Z" -skip 0 -top 100 -queuedns 1111
```
Making all of these changes further streamlined the .ps1 scripts themselves, new functions are shorter and easier to go through, and will allow for easier expansion to other XAPI endpoints with future functions.  
Older code is being moved to make it clear which files are latest, and that only new module will be updated.  
# 2025-03-15
- old scripts moved to `old-standalone_scripts` and will not be updated anymore
- new modular approach uploaded to `scripts_with_modules`, contains folder with modules (functions for repeatable tasks) and scripts themselves (plan is to have one per endpoint)
- inside `\modules\CommonFunctions.psm1` you have functions for commonly used tasks, eg, getting token, invoking requests, progress bars, formatting paths, showing help, showing sample data, exports to CSV/Excel, and so on, much of it is related to working with data AFTER it was fetched, as I've tailored it to my own needs, you can shorten it a lot if you just want raw data
- inside `\modules\DateTimeFunctions.psm1` you have functions that work with date/time formats converting them from/to diffeent ways of representing dates and times, converting to seconds, names of days, etc., again, much of this you may not need if you just need raw data, but it's there free to use
- to use new scripts make sure to download the folder and retain the file/folder structure
# 2025-03-14
- Added script for accessing `/xapi/v1/ReportAbandonedQueueCalls/Pbx.GetAbandonedQueueCallsData()`
Current files:  
- fetch_call_history.ps1 -> first script, using `CallHistoryView`, and no progress bar for HTTP request
- fetch_call_history2.ps1 -> same as first but improved with approximation of a progress for HTTP request
- fetch_call_report.ps1 -> variation of the script using `ReportCallLogData` endpoint that provides way more details than just the call logs in first two scripts
- fetch_abandoned_queue_calls_report.ps1 -> new script using `ReportAbandonedQueueCalls` endpoint for abandoned calls
# 2025-03-12
- First upload!
- Includes working scripts for `/xapi/v1/CallHistoryView` and `/xapi/v1/ReportCallLogData/Pbx.GetCallLogData()` endpoints
  

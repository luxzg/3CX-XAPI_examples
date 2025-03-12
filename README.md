# 3CX-XAPI_examples
Example scripts and code to work with 3CX V20 XAPI endpoints
  
# 2025-03-12
- First upload
- Working scripts for `/xapi/v1/CallHistoryView` and `/xapi/v1/ReportCallLogData/Pbx.GetCallLogData()` endpoints
- Developed with the help of 3CX community! Thanks everyone!
- Aimed at 3CX V20 XAPI
  
Community forum threads:
- https://www.3cx.com/community/threads/api-callhistoryview-filter-datetime-parameters.132426/
- https://www.3cx.com/community/threads/3cx-xapi-callhistoryview-code-explanations.132684/  
  
Scripts are well commented, just running the files will provide error to use the `-key` or look at help using `-help`.  
Rest of the usage is explained in help section.  
  
I will expand this readme with more information that was researched during development of these scripts.  
  
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

You will be using these credentials as `-key` and `-user` when calling the scripts. You can hardcode them inside script if you wish, though keep in mind that allows anyone that has the script to your while PBX system.

# Future content
I will add the following in a next few days:
- links to official docs (however don't expect much)
- links to 3rd party list if endpoints
- link to officiL github testing samples
- links to a few more community posts/threads
- link to OData specs and docs
- any other helpful links I find in meantime

I also plan to make a PHP sample, at least for basic token retrieval and calling few simpler endpoints, but don't have strict timeline yet.

If you have something useful to add let me know, I'd be glad to add it.

Note that API is relatively new, and there isn't much material about it. Official docs are lacking at best... so even these few samples required a lot if trials and errors. Hopefully this repo with readme and few samples helps people get started and gets the ball rolling.

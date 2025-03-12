# 3CX-XAPI_examples
Example scripts and code to work with 3CX V20 XAPI endpoints

# 2025-03-12
First upload
Working scripts for /xapi/v1/CallHistoryView and /xapi/v1/ReportCallLogData/Pbx.GetCallLogData() endpoints

Developed with help of 3CX community!
Aimed at 3CX V20 XAPI

Community forum threads:
https://www.3cx.com/community/threads/api-callhistoryview-filter-datetime-parameters.132426/
https://www.3cx.com/community/threads/3cx-xapi-callhistoryview-code-explanations.132684/

Scripts are well commented, running just the file will provide error to use the -key or look at help using -help
Rest of the usage is explained in help section

I will expand this readme with more information that was researched during development of these scripts.

Current files:
- fetch_call_history.ps1 -> first script, using CallHistoryView, and no progress bar for HTTP request
- fetch_call_history2.ps1 -> same as first but improved with approximation of a progress for HTTP request
- fetch_call_report.ps1 -> variation of the script using ReportCallLogData endpoint that provides way more details than just the call logs in first two scripts

Scripts were written to be universal, with one exception. Due to my own needs I've added names of days in Croatian language in the 3rd script. It also includes English names of days. Feel free to ignore or comment out that code, or reuse for other languages that you need. Other than that scripts should be well suited for any user.

Note that scripts require API integration user & key (secret), process of obtaiing one through 3CX Web UI console is explained in the community thread (first link)

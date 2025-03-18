# Define the module name
$ModuleName = "3CX_XAPI_Module"

# Get the module root directory
$ModuleRoot = $PSScriptRoot

# Import individual scripts (dot-sourcing)
. "$ModuleRoot\Get-3CXHelp.ps1"
. "$ModuleRoot\ActiveCalls.ps1"
. "$ModuleRoot\CallHistoryView.ps1"
. "$ModuleRoot\ReportAbandonedQueueCalls.ps1"
. "$ModuleRoot\ReportCallLogData.ps1"
. "$ModuleRoot\ReportQueuePerformanceOverview.ps1"

# Import additional helper modules if needed
Import-Module "$ModuleRoot\Modules\CommonFunctions.psm1" -Force
Import-Module "$ModuleRoot\Modules\DateTimeFunctions.psm1" -Force

# Export functions if scripts contain functions
Export-ModuleMember -Function *  # Exports all functions inside linked scripts

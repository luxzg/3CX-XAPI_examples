@{
    ModuleVersion		= '0.1.2'
    GUID				= 'a19a0b08-3bfd-47bf-b846-745906e33101'
    Author				= 'Luka Pribanić Lux'
    CompanyName			= 'none'
	Copyright			= 'Unlicence, see linked license'
    Description			= '3CX XAPI Module for accessing PBX data through XAPI'
    PowerShellVersion	= '5.1'
    RootModule			= '3CX_XAPI_Module.psm1'
    FunctionsToExport	= @('Get-3CXHelp','Get-XAPIToken','Invoke-XAPIRequestWithProgress','Get-ActiveCalls', 'Get-CallHistoryView', 'Get-ReportAbandonedQueueCalls', 'Get-ReportCallLogData', 'Get-ReportQueuePerformanceOverview')
    CmdletsToExport		= @()
    VariablesToExport	= '*'
    AliasesToExport		= '*'
    PrivateData			= @{
        PSData = @{
            Tags = @('3CX', 'XAPI')
            LicenseUri	= 'https://github.com/luxzg/3CX-XAPI_examples?tab=Unlicense-1-ov-file'
            ProjectUri	= 'https://github.com/luxzg/3CX-XAPI_examples'
        }
    }
}

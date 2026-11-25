# Versions of the components the Windows build downloads and packs. Change them here, then in the places 8-package.ps1 checks
# (Test-ComponentVersions): the file names in Apps.aip, Apps.Prerequisites.aip and OpenSearchStack.aip and the index folder in utils.ps1.
@{
    OpenSearch           = '3.5.0'      # OpenSearch.aip, OpenSearch-<version>.exe in Apps*.aip, Data\Index\v<version> in utils.ps1
    OpenSearchDashboards = '3.5.0'      # opensearch-dashboards-<version>-windows-x64.zip in OpenSearchStack.aip
    OpenResty            = '1.27.1.1'   # OpenResty.aip (/SetVersion), OpenResty-<version>.msi in Apps*.aip
    FluentBit            = '3.2.4'      # fluent-bit-<version>-win64.zip in OpenSearchStack.aip
}

# Versions of the components the Windows build downloads and packs. Change them here, then in the places package.ps1 checks
# (Test-ComponentVersions): the file names in Apps.aip, Apps.Prerequisites.aip and OpenSearchStack.aip and the index folder in utils.ps1.
@{
    OpenSearch           = '3.5.0'      # OpenSearch.aip, OpenSearch-<version>.exe in Apps*.aip, Data\Index\v<version> in utils.ps1
    OpenSearchDashboards = '3.5.0'      # opensearch-dashboards-<version>-windows-x64.zip in OpenSearchStack.aip
    OpenResty            = '1.27.1.1'   # OpenResty.aip (/SetVersion), OpenResty-<version>.msi in Apps*.aip
    FluentBit            = '3.2.4'      # fluent-bit-<version>-win64.zip in OpenSearchStack.aip
    NuGet                = '7.9.0'      # nuget.exe that restores the packages of the custom actions
    # Checksums of the downloads by the file name in their link (nuget.exe by nuget-<version>.exe): the published .sha512/.sha256 where the project
    # has one, else SHA-256 of the release file checked against its signature (OpenResty .asc, NuGet Authenticode); a new version needs its checksum here.
    Checksums            = @{
        'opensearch-3.5.0-windows-x64.zip'            = 'SHA512:4e5f386dc79911d4ad7d1b278ec2de4a60440c6810bb049464976c76503c1534304426a72d20790a92c19999e14693e34ea14421cd1113c22d6342093ec29951'
        'ingest-attachment-3.5.0.zip'                 = 'SHA512:52e7ebb1ea60f714d483ae0acd275912af128a7e47a323e02d209ac24df72eab47965e6edfeaefe3d6efa703fcd52848d419dc018f2bf43864445f68776a046f'
        'opensearch-dashboards-3.5.0-windows-x64.zip' = 'SHA512:94d05385ce00482aa87bb9ac77a6fa68575d78d61e6ca7a73caee9b9874e87c0428f12172bab40b187e94830feb21e5194ee13fb1931209437dad3f434d31ec5'
        'openresty-1.27.1.1-win64.zip'                = 'SHA256:655399594d66c3209cb650c19f87779719d63a2af520e2a93e094fedaef22947'
        'fluent-bit-3.2.4-win64.zip'                  = 'SHA256:5cefb29e17cf6dd3bd6a321a90406c120a01b11376acbee7e43844ea0e72a1b7'
        'nuget-7.9.0.exe'                             = 'SHA256:992d70cac5b06c38efec91806caba64cdcc07e6d963a0959dbbbaf264d33b800'
    }
}

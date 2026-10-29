# ジョブごとの実行時設定。パス、出力ファイル名、閾値などを定義します。
# ジョブの実装定義は foundation.jobs.psd1 に分離します。
@{
    Common = @{
        DebuggerUrl = 'http://localhost:9222/json'

        Logging = @{
            Level = 'Info'
            Console = $true
            File = $false
            Directory = 'logs'
        }

        Cdp = @{
            ConnectTimeoutSeconds = 15
            CommandTimeoutSeconds = 30
        }
    }

    Jobs = @{
        InstalledAppExport = @{
            TempDirectory = 'monthly\tmp'
            DownloadDirectory = 'monthly\Downloads'
            DownloadFilePrefix = 'app_list_'
            FailureCsvFileName = 'installed_app_export_error_list.csv'
            DownloadTimeoutSeconds = 120
            DownloadStableSeconds = 2
            DetailPanelCloseWaitSeconds = 3
            MaxScanLoops = 500
            SameScrollLimit = 2
        }

        ScanTargetSync = @{
            InputCsvPath = '%USERPROFILE%\Downloads\sensor_devices.csv'
            OutputDirectory = 'weekly\Downloads'
            CsvErrorFileName = 'scan_target_sync_error_list.csv'
            FailureCsvFileName = 'scan_target_sync_failure_list.csv'
            DaysThreshold = 7
            MaxScanLoops = 500
            SameScrollLimit = 5
        }


        DeviceListExport = @{
            TempDirectory = 'weekly\tmp\device_list_export'
            DownloadDirectory = 'weekly\Downloads'
            DownloadedCsvFileNamePattern = '^.+\.csv$'
            OutputFileNameTemplate = 'sensor_devices_{0}.csv'
            DownloadTimeoutSeconds = 120
            DownloadStableSeconds = 2
            NavigationTimeoutSeconds = 20
            TaskMenuTimeoutSeconds = 10
        }

        LastMonthInstallExtract = @{
            TargetDirectory = 'monthly\Downloads'
            OutputCsvFileName = 'pc_installation.csv'
            FailureCsvFileName = 'pc_installation_failure_list.csv'
            FileNamePattern = '^.+_(PCXX-\d{2}-\d{3})\.csv$'
            RequiredHeaders = @(
                'アプリ名'
                'バージョン'
                '導入日'
            )
        }

        WeeklyScanTargetSync = @{
        }

        MonthlyInstallReport = @{
            RunRootDirectory = 'monthly\runs'
        }

    }
}

# ジョブの実装定義。ModulePath, CommandName, DomFeaturePaths または UsesDom を定義します。
# DOMを使うジョブは DomFeaturePath(s) を指定し、DOMを使わないジョブは UsesDom = $false を指定します。
# 実行時設定は foundation.config.psd1 の Jobs に分離します。
@{
    Jobs = @{
        InstalledAppExport = @{
            ModulePath = 'modules\InstalledAppExport\InstalledAppExport.psm1'
            CommandName = 'Invoke-InstalledAppExportJob'
            DomFeaturePaths = @(
                'dom\features\installed-app-export\contract.js'
                'dom\features\installed-app-export\list.js'
                'dom\features\installed-app-export\detail.js'
                'dom\features\installed-app-export\apps.js'
                'dom\features\installed-app-export\actions.js'
                'dom\features\installed-app-export\index.js'
            )
        }

        ScanTargetSync = @{
            ModulePath = 'modules\ScanTargetSync\ScanTargetSync.psm1'
            CommandName = 'Invoke-ScanTargetSyncJob'
            DomFeaturePaths = @(
                'dom\features\scan-target-sync\contract.js'
                'dom\features\scan-target-sync\list.js'
                'dom\features\scan-target-sync\actions.js'
                'dom\features\scan-target-sync\index.js'
            )
        }


        DeviceListExport = @{
            ModulePath = 'modules\DeviceListExport\DeviceListExport.psm1'
            CommandName = 'Invoke-DeviceListExportJob'
            DomFeaturePaths = @(
                'dom\features\device-list-export\contract.js'
                'dom\features\device-list-export\navigation.js'
                'dom\features\device-list-export\export.js'
                'dom\features\device-list-export\index.js'
            )
        }

        LastMonthInstallExtract = @{
            ModulePath = 'modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1'
            CommandName = 'Invoke-LastMonthInstallExtractJob'
            UsesDom = $false
        }

        WeeklyScanTargetSync = @{
            ModulePath = 'modules\CompositeJobs\CompositeJobs.psm1'
            CommandName = 'Invoke-WeeklyScanTargetSyncJob'
            UsesDom = $false
        }

        MonthlyInstallReport = @{
            ModulePath = 'modules\CompositeJobs\CompositeJobs.psm1'
            CommandName = 'Invoke-MonthlyInstallReportJob'
            UsesDom = $false
        }

    }
}

(function registerInstalledAppExportDetailPart(root) {
    const part = {
        isDetailPanelVisible() {
            const panel = document.querySelector(this.selectors.frontPanel);
            return !!panel && this.isVisible(panel);
        },

        getDetailAssetName() {
            const panel = document.querySelector(this.selectors.frontPanel);

            if (!panel || !this.isVisible(panel)) {
                return '';
            }

            const nameEl =
                panel.querySelector('.title-text[ng-bind="detail.item.name"]') ||
                panel.querySelector('span[ng-bind="detail.item.name"]');

            if (!nameEl || !this.isVisible(nameEl)) {
                return '';
            }

            return this.norm(nameEl.textContent || nameEl.getAttribute('data-tooltip'));
        },

        isDetailPanelReadyFor(assetName) {
            return this.isDetailPanelVisible() &&
                   this.getDetailAssetName() === assetName;
        },

        validateClickedRowContext(dataId, assetName) {
            const checks = [];
            const selected = this.getSelectedAssetRow();
            const detailAssetName = this.getDetailAssetName();

            checks.push(this.makeCheck(
                'assetList.selectedRow.unique',
                selected && selected.ok === true,
                'fatal',
                '選択行が一意であること',
                { selected }
            ));

            checks.push(this.makeCheck(
                'assetList.selectedRow.matchesClickedRow',
                selected &&
                selected.ok === true &&
                selected.dataId === dataId &&
                selected.assetName === assetName,
                'fatal',
                '選択行がクリック対象の data-id + 端末名 と一致すること',
                { selected, expected: { dataId, assetName } }
            ));

            checks.push(this.makeCheck(
                'detailPanel.root.visible',
                this.isDetailPanelVisible(),
                'fatal',
                '行クリック後に詳細パネルが可視であること',
                { frontPanel: this.elementDebug(document.querySelector(this.selectors.frontPanel)) }
            ));

            checks.push(this.makeCheck(
                'detailPanel.assetName.exists',
                !!detailAssetName,
                'fatal',
                '詳細パネル内から端末名を取得できること',
                { detailAssetName }
            ));

            checks.push(this.makeCheck(
                'detailPanel.assetName.matchesClickedRow',
                detailAssetName === assetName,
                'fatal',
                '詳細パネルの端末名がクリック対象行と一致すること',
                { expected: assetName, actual: detailAssetName }
            ));

            return this.contractResult('clickedRowContext', checks, {
                dataId,
                assetName,
                detailAssetName
            });
        },

    };

    root.__InstalledAppExportDomHelperParts = root.__InstalledAppExportDomHelperParts || [];
    root.__InstalledAppExportDomHelperParts.push(part);

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = part;
    }

    return true;
})(typeof window !== 'undefined' ? window : globalThis);

(function registerInstalledAppExportActionsPart(root) {
    const part = {
        closeDetailPanel() {
            const panel = document.querySelector(this.selectors.frontPanel);

            if (!panel || !this.isVisible(panel)) {
                return {
                    ok: true,
                    severity: 'info',
                    action: 'detail-panel-already-hidden',
                    alreadyClosed: true,
                    message: '詳細パネルは非表示です。DOM上に残っていても契約違反とはみなしません。'
                };
            }

            const rawButtons = this.uniqueElements([
                panel.querySelector('.panel-close button.close-btn'),
                panel.querySelector('button[ng-click="detail.close()"]')
            ]);

            const buttons = rawButtons
                .filter(button => this.isVisible(button))
                .filter(button => !this.isDisabled(button));

            if (buttons.length !== 1) {
                return {
                    ok: false,
                    severity: 'warning',
                    action: 'detail-panel-close-button-not-unique',
                    message: '詳細パネルの close は cleanup であり、失敗だけでは fatal にしません。次行クリック後の詳細名一致を主契約にします。',
                    candidateCount: buttons.length,
                    candidates: rawButtons.map(button => this.elementDebug(button))
                };
            }

            this.clickElement(buttons[0]);

            return {
                ok: true,
                severity: 'info',
                action: 'close-detail-panel-requested',
                alreadyClosed: false,
                message: 'close を要求しました。短時間の非表示確認は PowerShell 側で warning として扱います。'
            };
        },

        isDetailPanelClosed() {
            const panel = document.querySelector(this.selectors.frontPanel);

            if (!panel) {
                return true;
            }

            return !this.isVisible(panel);
        }
    };

    root.__InstalledAppExportDomHelperParts = root.__InstalledAppExportDomHelperParts || [];
    root.__InstalledAppExportDomHelperParts.push(part);

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = part;
    }

    return true;
})(typeof window !== 'undefined' ? window : globalThis);

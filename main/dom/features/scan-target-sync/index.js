(function(factory) {
    if (typeof module !== 'undefined' && module.exports) {
        module.exports = { createScanTargetSyncDomHelper: factory };
    }

    if (typeof window !== 'undefined' && typeof document !== 'undefined') {
        window.__ScanTargetSyncDomHelper = factory(window, document);
    }

    return true;
})(function createScanTargetSyncDomHelper(window, document) {
    const domHelper = {
        version: 'scan-target-sync_ver1.00_2026/06',
        selectors: {
            viewport: '#viewport',
            searchBox: 'input#searchBox[name="searchBox"]',
            draggableRow: '[class*="DataTable__row"]',
            headerCell: '[class*="DataTable__header"]',
            dataCell: '[class*="DataTable__cell"]',
            checkboxLabel: 'label',
            checkboxInput: 'input[type="checkbox"]',
            menuItem: '[role="menuitem"]'
        },

        requiredHeaders: [
            'ホスト名',
            '接続状態',
            '利用者',
            '最終通信日時',
            '手動スキャンの開始',
            '手動スキャンの完了'
        ],

        // 初期DOM契約で確定した操作スコープを保持する。
        // ループ中は契約全体を再評価せず、このコンテキストだけを使って軽量にON/OFFを同期する。
        _operationContext: null
    };

    const parts = window.__ScanTargetSyncDomHelperParts || [];
    for (const part of parts) {
        Object.assign(domHelper, part);
    }

    return domHelper;
});

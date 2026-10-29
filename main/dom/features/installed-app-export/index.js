(function(factory) {
    if (typeof module !== 'undefined' && module.exports) {
        module.exports = { createInstalledAppExportDomHelper: factory };
    }

    if (typeof window !== 'undefined' && typeof document !== 'undefined') {
        window.__InstalledAppExportDomHelper = factory(window, document);
    }

    return true;
})(function createInstalledAppExportDomHelper(window, document) {
    const domHelper = {
        version: 'installed-app-export_ver1.00_2026/06',
        selectors: {
            contents: '#contents',
            breadcrumbPanel: '#breadcrumb-panel',

            // 固定列側ヘッダ。
            // 画面・グリッド設定により、端末名列が固定列側に存在する場合がある。
            fixedHeaderRow: '#asset-grid_headers_fixed tr[data-header-row][role="row"]',

            // 通常列側ヘッダ。
            // 画面・グリッド設定により、端末名列が通常列側に存在する場合がある。
            mainHeaderRow: '#asset-grid_headers tr[data-header-row][role="row"]',

            selectorHeader: '#asset-grid___selector__',

            // 固定列側ボディ。
            // どちらに端末名セルがあるかは、ヘッダー文言から契約チェック時に解決する。
            fixedGrid: '#asset-grid_fixed',

            // 通常列側ボディ。
            // どちらに端末名セルがあるかは、ヘッダー文言から契約チェック時に解決する。
            mainGrid: '#asset-grid',

            fixedBodyContainer: '#asset-grid_fixedBodyContainer',
            mainScrollContainer: '#asset-grid_scroll',
            gridContainer: '#asset-grid_container',

            frontPanel: '#detail-panel',
            appTab: '#detail-panel .app-pane',
            appGrid: '#app-grid',
            appGridHeaders: '#app-grid_headers th span.ui-iggrid-headertext',
            appRadio: 'input#app-list-radio[type="radio"]',
            appRadioLabel: 'label[for="app-list-radio"]'
        },

        requiredAppHeaders: [
            'アプリ名',
            'バージョン',
            '導入日'
        ],

    };

    const parts = window.__InstalledAppExportDomHelperParts || [];
    for (const part of parts) {
        Object.assign(domHelper, part);
    }

    return domHelper;
});

(function(factory) {
    if (typeof module !== 'undefined' && module.exports) {
        module.exports = { createDeviceListExportDomHelper: factory };
    }

    if (typeof window !== 'undefined' && typeof document !== 'undefined') {
        window.__DeviceListExportDomHelper = factory(window, document);
    }

    return true;
})(function createDeviceListExportDomHelper(window, document) {
    const domHelper = {
        version: 'device-list-export_ver1.00_2026/06',
        selectors: {
            viewport: '#viewport'
        },
        _lastExportClickResult: null
    };

    const parts = window.__DeviceListExportDomHelperParts || [];
    for (const part of parts) {
        Object.assign(domHelper, part);
    }

    return domHelper;
});

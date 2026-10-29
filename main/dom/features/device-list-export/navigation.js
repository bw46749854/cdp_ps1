(function registerDeviceListExportNavigationPart(root) {
    const part = {
        resolveSensorNavigation() {
            const explicitSelector = '[data-components="sidenav-item-devices"]';
            const explicitMatches = [...document.querySelectorAll(explicitSelector)]
                .filter(el => this.isVisible(el));

            if (explicitMatches.length === 1) {
                const element = explicitMatches[0];
                return {
                    ok: true,
                    element,
                    count: 1,
                    reason: 'explicit-data-components',
                    candidates: [this.elementDebug(element)],
                    summary: this.elementDebug(element)
                };
            }

            if (explicitMatches.length > 1) {
                return {
                    ok: false,
                    element: null,
                    count: explicitMatches.length,
                    reason: 'multiple-explicit-data-components',
                    candidates: explicitMatches.map(el => this.elementDebug(el)).slice(0, 20),
                    summary: null
                };
            }

            const candidates = [];
            const seen = new Set();
            const pushCanonical = (element, sourceElement, reason) => {
                if (!element || seen.has(element)) return;
                seen.add(element);
                candidates.push({
                    element,
                    sourceElement: sourceElement || element,
                    reason,
                    debug: this.elementDebug(element),
                    sourceDebug: this.elementDebug(sourceElement || element)
                });
            };

            const textSelectors = [
                '[role="menuitem"]',
                '[title="センサー"]',
                'a',
                'button',
                'span'
            ];

            for (const selector of textSelectors) {
                for (const el of [...document.querySelectorAll(selector)]) {
                    const text = this.norm(el.textContent);
                    const title = this.norm(el.getAttribute('title'));
                    const hasExpectedText = text === 'センサー' || title === 'センサー';
                    if (!hasExpectedText) continue;

                    const navScope = el.closest('nav, [class*="SideNav"], [class*="sidenav"], [role="menu"]');
                    if (!navScope) continue;

                    const canonical = el.closest('[role="menuitem"], a, button, [data-components]') || el;
                    pushCanonical(canonical, el, 'text-or-title-in-navigation');
                }
            }

            const visible = candidates.filter(x => this.isVisible(x.element));
            const element = visible.length === 1 ? visible[0].element : null;

            return {
                ok: visible.length === 1,
                element,
                count: visible.length,
                reason: visible.length === 1 ? visible[0].reason : 'fallback-candidate-count',
                candidates: visible.map(x => ({ element: x.debug, source: x.sourceDebug, reason: x.reason })).slice(0, 20),
                summary: element ? this.elementDebug(element) : null
            };
        },

        resolveDeviceDefaultNavigation() {
            const exactSelector = 'span[data-label="true"][data-id="1"]';
            const exactMatches = [...document.querySelectorAll(exactSelector)]
                .filter(el => {
                    const text = this.norm(el.textContent);
                    return (text === 'デバイス (既定グループ)' || text === 'デバイス（既定グループ）') && this.isVisible(el);
                });

            if (exactMatches.length === 1) {
                const element = exactMatches[0];
                return {
                    ok: true,
                    element,
                    count: 1,
                    reason: 'exact-data-label-data-id',
                    candidates: [this.elementDebug(element)],
                    summary: this.elementDebug(element)
                };
            }

            if (exactMatches.length > 1) {
                return {
                    ok: false,
                    element: null,
                    count: exactMatches.length,
                    reason: 'multiple-exact-data-label-data-id',
                    candidates: exactMatches.map(el => this.elementDebug(el)).slice(0, 20),
                    summary: null
                };
            }

            const candidates = [];
            const seen = new Set();
            for (const el of [...document.querySelectorAll('span[data-label="true"], [role="treeitem"] span, [role="treeitem"] [data-label="true"]')]) {
                const text = this.norm(el.textContent);
                const dataId = this.norm(el.getAttribute('data-id'));
                const hasExactLabel = text === 'デバイス (既定グループ)' || text === 'デバイス（既定グループ）';
                const isLabel = el.getAttribute('data-label') === 'true';
                const inTree = !!el.closest('[class*="tree"], [role="tree"], [role="treeitem"], [class*="GroupView"]');

                if (!hasExactLabel || (!isLabel && !inTree)) continue;
                if (seen.has(el)) continue;
                seen.add(el);

                candidates.push({
                    element: el,
                    debug: this.elementDebug(el),
                    reason: dataId === '1' ? 'data-id-1-text' : 'tree-label-text'
                });
            }

            const visible = candidates.filter(x => this.isVisible(x.element));
            const element = visible.length === 1 ? visible[0].element : null;

            return {
                ok: visible.length === 1,
                element,
                count: visible.length,
                reason: visible.length === 1 ? visible[0].reason : 'fallback-candidate-count',
                candidates: visible.map(x => x.debug).slice(0, 20),
                summary: element ? this.elementDebug(element) : null
            };
        },
    };

    root.__DeviceListExportDomHelperParts = root.__DeviceListExportDomHelperParts || [];
    root.__DeviceListExportDomHelperParts.push(part);

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = part;
    }
})(typeof window !== 'undefined' ? window : globalThis);

(function registerInstalledAppExportContractPart(root) {
    const part = {
        norm(s) {
            return (s || '').replace(/[\s\u00a0\u3000]+/g, ' ').trim();
        },

        uniqueElements(elements) {
            return [...new Set(elements.filter(Boolean))];
        },

        isVisible(el) {
            if (!el) return false;

            const r = el.getBoundingClientRect();
            const s = window.getComputedStyle(el);

            return r.width > 0 &&
                   r.height > 0 &&
                   s.display !== 'none' &&
                   s.visibility !== 'hidden' &&
                   s.opacity !== '0';
        },

        isDisabled(el) {
            if (!el) return true;

            return el.disabled === true ||
                   el.hasAttribute('disabled') ||
                   el.getAttribute('aria-disabled') === 'true' ||
                   !!el.closest('[aria-disabled="true"]');
        },

        elementDebug(el) {
            if (!el) return null;

            return {
                tagName: el.tagName,
                id: el.id || '',
                className: typeof el.className === 'string' ? el.className : '',
                text: this.norm(el.textContent),
                visible: this.isVisible(el),
                disabled: this.isDisabled(el),
                ariaDescribedby: el.getAttribute('aria-describedby'),
                ngBind: el.getAttribute('ng-bind'),
                downloadUrl: el.getAttribute('data-download-url'),
                onBeforeDownload: el.getAttribute('data-before-download')
            };
        },

        isDomNode(value) {
            return !!value && typeof Node !== 'undefined' && value instanceof Node;
        },

        domNodeDebug(value) {
            if (!this.isDomNode(value)) return null;
            if (typeof Element !== 'undefined' && value instanceof Element) {
                return this.elementDebug(value);
            }

            return {
                nodeType: value.nodeType,
                nodeName: value.nodeName || '',
                text: this.norm(value.textContent || '')
            };
        },

        sanitizeForReturn(value, depth, seen) {
            const maxDepth = 8;
            const currentDepth = depth || 0;
            const visited = seen || new WeakSet();

            if (value === null || value === undefined) return value;

            const valueType = typeof value;
            if (valueType === 'string' || valueType === 'number' || valueType === 'boolean') return value;
            if (valueType === 'bigint') return String(value);
            if (valueType === 'function' || valueType === 'symbol') return undefined;

            if (this.isDomNode(value)) {
                return this.domNodeDebug(value);
            }

            if (currentDepth >= maxDepth) {
                return '[MaxDepth]';
            }

            if (Array.isArray(value)) {
                return value.map(x => this.sanitizeForReturn(x, currentDepth + 1, visited));
            }

            if (valueType === 'object') {
                if (visited.has(value)) return '[Circular]';
                visited.add(value);

                const out = {};
                for (const key of Object.keys(value)) {
                    const sanitized = this.sanitizeForReturn(value[key], currentDepth + 1, visited);
                    if (sanitized !== undefined) out[key] = sanitized;
                }
                return out;
            }

            return String(value);
        },

        makeCheck(name, ok, severity, message, details) {
            return {
                name,
                ok: !!ok,
                severity: severity || 'fatal',
                message: message || '',
                details: this.sanitizeForReturn(details || {})
            };
        },

        contractResult(scope, checks, details) {
            const fatalCount = checks.filter(x => !x.ok && x.severity === 'fatal').length;
            const warningCount = checks.filter(x => !x.ok && x.severity === 'warning').length;

            return {
                scope,
                ok: fatalCount === 0,
                fatalCount,
                warningCount,
                checks: this.sanitizeForReturn(checks || []),
                details: this.sanitizeForReturn(details || {})
            };
        },

        throwContractIfFatal(result) {
            if (!result || result.fatalCount === 0) {
                return;
            }

            const fatalChecks = result.checks.filter(x => !x.ok && x.severity === 'fatal');

            throw new Error(
                'DOM契約違反: ' +
                result.scope +
                ' / fatal=' +
                JSON.stringify(fatalChecks)
            );
        },

        clickElement(el) {
            if (!el) {
                throw new Error('clickElement: element is null');
            }

            el.scrollIntoView({
                block: 'center',
                inline: 'center'
            });

            const r = el.getBoundingClientRect();
            const x = r.left + (r.width / 2);
            const y = r.top + (r.height / 2);

            const eventOptions = {
                bubbles: true,
                cancelable: true,
                view: window,
                clientX: x,
                clientY: y
            };

            el.dispatchEvent(new window.MouseEvent('mouseover', eventOptions));
            el.dispatchEvent(new window.MouseEvent('mousedown', eventOptions));
            el.dispatchEvent(new window.MouseEvent('mouseup', eventOptions));
            el.dispatchEvent(new window.MouseEvent('click', eventOptions));
        },

        getAssetPageTextCandidates() {
            const selectors = [
                '#breadcrumb-panel',
                '#breadcrumb-panel .breadcrumb',
                '.breadcrumb',
                '[aria-label]',
                'h1',
                'h2',
                '.page-title',
                '.title'
            ];
            const values = [];

            for (const selector of selectors) {
                for (const el of [...document.querySelectorAll(selector)]) {
                    if (!this.isVisible(el)) continue;
                    const text = this.norm(el.textContent);
                    if (text) values.push(text);
                }
            }

            if (document.title) {
                values.push(this.norm(document.title));
            }

            return [...new Set(values.filter(Boolean))];
        },

        detectAssetPageIdentity() {
            const checks = [];
            const contents = document.querySelector(this.selectors.contents);
            const breadcrumbPanel = document.querySelector(this.selectors.breadcrumbPanel);
            const pageTexts = this.getAssetPageTextCandidates();
            const hasAssetListText = pageTexts.some(text => text.includes('端末一覧'));

            checks.push(this.makeCheck(
                'identity.contents.exists',
                !!contents,
                'fatal',
                '#contents が存在すること',
                { contents: this.elementDebug(contents) }
            ));

            checks.push(this.makeCheck(
                'identity.contents.class.asset',
                !!contents && contents.classList.contains('asset'),
                'fatal',
                '#contents の class に asset が含まれること',
                { className: contents ? contents.className : '' }
            ));

            checks.push(this.makeCheck(
                'identity.contents.notPatchList',
                !contents || !contents.classList.contains('patch-list'),
                'fatal',
                '#contents の class に patch-list が含まれないこと',
                { className: contents ? contents.className : '' }
            ));

            checks.push(this.makeCheck(
                'identity.titleOrBreadcrumb.assetList',
                hasAssetListText,
                'fatal',
                'パンくず、画面タイトル、または document.title から「端末一覧」を確認できること',
                {
                    pageTexts,
                    breadcrumbPanel: this.elementDebug(breadcrumbPanel),
                    documentTitle: document.title || ''
                }
            ));

            return this.contractResult('assetPageIdentity', checks, {
                className: contents ? contents.className : '',
                pageTexts,
                hasAssetListText
            });
        },

        validateAssetPageContract() {
            const checks = [];
            const contents = document.querySelector(this.selectors.contents);
            const breadcrumbPanel = document.querySelector(this.selectors.breadcrumbPanel);
            const pageTexts = this.getAssetPageTextCandidates();
            const hasAssetListText = pageTexts.some(text => text.includes('端末一覧'));
            const mainGrid = document.querySelector(this.selectors.mainGrid);
            const fixedGrid = document.querySelector(this.selectors.fixedGrid);
            const gridContainer = document.querySelector(this.selectors.gridContainer);

            checks.push(this.makeCheck(
                'page.contents.exists',
                !!contents,
                'fatal',
                '#contents が存在すること',
                { contents: this.elementDebug(contents) }
            ));

            checks.push(this.makeCheck(
                'page.contents.class.asset',
                !!contents && contents.classList.contains('asset'),
                'fatal',
                '#contents の class に asset が含まれること',
                { className: contents ? contents.className : '' }
            ));

            checks.push(this.makeCheck(
                'page.contents.notPatchList',
                !contents || !contents.classList.contains('patch-list'),
                'fatal',
                '#contents の class に patch-list が含まれないこと',
                { className: contents ? contents.className : '' }
            ));

            checks.push(this.makeCheck(
                'page.titleOrBreadcrumb.assetList',
                hasAssetListText,
                'fatal',
                'パンくず、画面タイトル、または document.title から「端末一覧」を確認できること',
                {
                    pageTexts,
                    breadcrumbPanel: this.elementDebug(breadcrumbPanel),
                    documentTitle: document.title || ''
                }
            ));

            checks.push(this.makeCheck(
                'page.grid.exists',
                !!mainGrid || !!fixedGrid || !!gridContainer,
                'fatal',
                'asset-grid 系の一覧DOMが存在すること',
                {
                    mainGrid: this.elementDebug(mainGrid),
                    fixedGrid: this.elementDebug(fixedGrid),
                    gridContainer: this.elementDebug(gridContainer)
                }
            ));

            return this.contractResult('assetPage', checks, {
                className: contents ? contents.className : '',
                pageTexts,
                hasAssetListText
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

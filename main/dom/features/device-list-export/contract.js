(function registerDeviceListExportContractPart(root) {
    const part = {
        norm(s) {
            return (s || '').replace(/[\s\u00a0\u3000]+/g, ' ').trim();
        },

        uniqueElements(elements) {
            return [...new Set((elements || []).filter(Boolean))];
        },

        uniqueValues(values) {
            return [...new Set((values || []).filter(x => x !== null && x !== undefined && x !== ''))];
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
                   !!el.closest('[disabled]') ||
                   !!el.closest('[aria-disabled="true"]') ||
                   [...(el.classList || [])].some(x => x.indexOf('disabled') >= 0) ||
                   !!el.closest('[class*="disabled"]');
        },

        isClickable(el) {
            return !!el && this.isVisible(el) && !this.isDisabled(el);
        },

        elementDebug(el) {
            if (!el) return null;
            const rect = el.getBoundingClientRect();
            return {
                tagName: el.tagName,
                id: el.id || '',
                className: typeof el.className === 'string' ? el.className : '',
                text: this.norm(el.textContent),
                visible: this.isVisible(el),
                disabled: this.isDisabled(el),
                role: el.getAttribute('role'),
                title: el.getAttribute('title'),
                dataId: el.getAttribute('data-id'),
                dataComponents: el.getAttribute('data-components'),
                ariaExpanded: el.getAttribute('aria-expanded'),
                ariaHaspopup: el.getAttribute('aria-haspopup'),
                rect: { width: rect.width, height: rect.height }
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

        sleep(ms) {
            return new Promise(resolve => window.setTimeout(resolve, ms));
        },

        parseSensorCountText(text) {
            const normalized = this.norm(text).replace(/,/g, '');
            const sensorMatch = normalized.match(/センサー\s*[:：]\s*(\d+)/);
            const slash = normalized.match(/\/\s*(\d+)\s*(?:件)?\s*$/);
            const total = normalized.match(/(?:全|合計)\s*(\d+)\s*(?:件)?/);
            const simple = normalized.match(/^(\d+)\s*(?:件)?$/);

            if (sensorMatch) return Number(sensorMatch[1]);
            if (slash) return Number(slash[1]);
            if (total) return Number(total[1]);
            if (simple) return Number(simple[1]);

            return null;
        },

        getDeviceListTotalCount() {
            const candidates = [];

            for (const el of [...document.querySelectorAll('span, div')]) {
                if (!this.isVisible(el)) continue;

                const text = this.norm(el.textContent);
                const title = this.norm(el.getAttribute('title'));

                if (text.indexOf('センサー') >= 0) {
                    candidates.push({ el, value: this.parseSensorCountText(text), text, source: 'text' });
                }

                if (title.indexOf('センサー') >= 0) {
                    candidates.push({ el, value: this.parseSensorCountText(title), text: title, source: 'title' });
                }
            }

            const valid = candidates.filter(x => x.value !== null && !Number.isNaN(x.value));
            const values = this.uniqueValues(valid.map(x => String(x.value))).map(x => Number(x));

            return {
                ok: values.length === 1,
                value: values.length === 1 ? values[0] : null,
                values,
                candidates: candidates.slice(0, 20).map(x => ({
                    value: x.value,
                    text: x.text,
                    source: x.source,
                    element: this.elementDebug(x.el)
                }))
            };
        },

        getViewport() {
            const matches = [...document.querySelectorAll(this.selectors.viewport)];
            return matches.length === 1 ? matches[0] : null;
        },

        getPageTextCandidates() {
            const selectors = [
                '#viewport',
                '[class*="Breadcrumb"]',
                '[class*="breadcrumb"]',
                '[aria-label]',
                '[title]',
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
                    const title = this.norm(el.getAttribute('title'));
                    const aria = this.norm(el.getAttribute('aria-label'));
                    if (text) values.push(text);
                    if (title) values.push(title);
                    if (aria) values.push(aria);
                }
            }

            if (document.title) {
                values.push(this.norm(document.title));
            }

            return this.uniqueValues(values);
        },

        hasProductIdentityText(pageTexts) {
            const joined = pageTexts.join(' / ');
            return joined.indexOf('ExampleSecurity') >= 0 ||
                   joined.indexOf('Cloud Service') >= 0 ||
                   joined.indexOf('Vendor') >= 0;
        },

        hasSensorText(pageTexts) {
            return pageTexts.join(' / ').indexOf('センサー') >= 0;
        },

        hasDeviceDefaultText(pageTexts) {
            const joined = pageTexts.join(' / ');
            return joined.indexOf('デバイス (既定グループ)') >= 0 ||
                   joined.indexOf('デバイス（既定グループ）') >= 0;
        },

        buildIdentityChecks(scopeName, options) {
            const contractOptions = options || {};
            const requireDocumentReady = contractOptions.requireDocumentReady === true;
            const requireDeviceDefault = contractOptions.requireDeviceDefault === true;
            const checks = [];
            const viewportMatches = [...document.querySelectorAll(this.selectors.viewport)];
            const viewport = viewportMatches.length === 1 ? viewportMatches[0] : null;
            const pageTexts = this.getPageTextCandidates();
            const productIdentity = this.hasProductIdentityText(pageTexts);
            const sensorText = this.hasSensorText(pageTexts);
            const deviceDefaultText = this.hasDeviceDefaultText(pageTexts);
            const sensorNav = this.resolveSensorNavigation();

            if (requireDocumentReady) {
                checks.push(this.makeCheck(
                    `${scopeName}.document.ready`,
                    document.readyState === 'complete',
                    'fatal',
                    'document.readyState が complete であること',
                    { readyState: document.readyState }
                ));
            }

            checks.push(this.makeCheck(
                `${scopeName}.viewport.unique`,
                viewportMatches.length === 1,
                'fatal',
                '#viewport が一意に存在すること',
                { count: viewportMatches.length, viewport: this.elementDebug(viewport) }
            ));

            checks.push(this.makeCheck(
                `${scopeName}.product.identity`,
                productIdentity,
                'fatal',
                '製品タイトルまたは画面ルートがExampleSecurity Cloud Serviceであること',
                { pageTexts, documentTitle: document.title || '' }
            ));

            checks.push(this.makeCheck(
                `${scopeName}.sensor.text`,
                sensorText,
                'fatal',
                '画面上の可視テキストまたは document.title から「センサー」を確認できること',
                { pageTexts, documentTitle: document.title || '' }
            ));

            checks.push(this.makeCheck(
                `${scopeName}.navigation.sensor.unique`,
                sensorNav.ok,
                'fatal',
                '左ナビまたはナビゲーション内の「センサー」が一意に特定できること',
                sensorNav
            ));

            if (requireDeviceDefault) {
                checks.push(this.makeCheck(
                    `${scopeName}.deviceDefault.text`,
                    deviceDefaultText,
                    'fatal',
                    '画面上の可視テキストから「デバイス (既定グループ)」を確認できること',
                    { pageTexts, documentTitle: document.title || '' }
                ));
            }

            return { checks, pageTexts, viewport, productIdentity, sensorText, deviceDefaultText, sensorNav };
        },

        detectDeviceListExportPageIdentity() {
            const identity = this.buildIdentityChecks('page.identity', { requireDeviceDefault: true });
            return this.contractResult('deviceListExportPageIdentity', identity.checks, {
                pageTexts: identity.pageTexts,
                productIdentity: identity.productIdentity,
                sensorText: identity.sensorText,
                deviceDefaultText: identity.deviceDefaultText,
                sensorNavigation: identity.sensorNav
            });
        },

        validateInitialContract() {
            const identity = this.buildIdentityChecks('initial', { requireDocumentReady: true, requireDeviceDefault: true });
            const checks = identity.checks;
            const sensorNav = identity.sensorNav;

            checks.push(this.makeCheck(
                'navigation.sensor.clickable',
                sensorNav.ok && this.isClickable(sensorNav.element),
                'fatal',
                '「センサー」ナビゲーションが visible / enabled / clickable であること',
                { navigation: this.elementDebug(sensorNav.element) }
            ));

            return this.contractResult('deviceListExportInitial', checks, {
                pageTexts: identity.pageTexts,
                deviceDefaultText: identity.deviceDefaultText,
                sensorNavigation: sensorNav.summary
            });
        },

        validateExportPageContract() {
            const identity = this.buildIdentityChecks('exportPage', { requireDocumentReady: true, requireDeviceDefault: true });
            const checks = identity.checks;
            const deviceDefault = this.resolveDeviceDefaultNavigation();
            const taskButton = this.resolveTaskButton();
            const totalCount = this.getDeviceListTotalCount();

            checks.push(this.makeCheck(
                'navigation.deviceDefault.unique',
                deviceDefault.ok,
                'fatal',
                '「デバイス (既定グループ)」が期待する意味で一意に存在すること',
                deviceDefault
            ));

            checks.push(this.makeCheck(
                'page.deviceCount.readable',
                totalCount.ok && totalCount.value !== null,
                'fatal',
                '画面上の「センサー: <件数>」から一覧件数を一意に取得できること',
                totalCount
            ));

            checks.push(this.makeCheck(
                'toolbar.task.unique',
                taskButton.ok,
                'fatal',
                '対象画面のツールバー内に「操作」ボタンが一意に存在すること',
                taskButton
            ));

            checks.push(this.makeCheck(
                'toolbar.task.clickable',
                taskButton.ok && this.isClickable(taskButton.element),
                'fatal',
                '操作ボタンが visible / enabled / clickable であり、設定メニュー等と誤認していないこと',
                { taskButton: this.elementDebug(taskButton.element) }
            ));

            return this.contractResult('deviceListExportPage', checks, {
                pageTexts: identity.pageTexts,
                deviceDefault: deviceDefault.summary,
                totalCount: totalCount.value,
                taskButton: taskButton.summary
            });
        },

        validateExportPostcondition() {
            const checks = [];
            const last = this._lastExportClickResult || null;
            checks.push(this.makeCheck(
                'export.postcondition.clickAccepted',
                !!last && last.ok === true && last.action === 'click-export',
                'fatal',
                'エクスポートクリックがDOM操作として受理されたこと',
                { lastExportClickResult: last }
            ));

            return this.contractResult('deviceListExportPostcondition', checks, {
                lastExportClickResult: last,
                url: window.location.href || ''
            });
        }
    };

    root.__DeviceListExportDomHelperParts = root.__DeviceListExportDomHelperParts || [];
    root.__DeviceListExportDomHelperParts.push(part);

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = part;
    }
})(typeof window !== 'undefined' ? window : globalThis);

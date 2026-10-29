(function registerScanTargetSyncContractPart(root) {
    const part = {
        norm(s) {
            return (s || '').replace(/[\s\u00a0\u3000]+/g, ' ').trim();
        },

        uniqueElements(elements) {
            return [...new Set(elements.filter(Boolean))];
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

        elementDebug(el) {
            if (!el) return null;

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
                ariaSelected: el.getAttribute('aria-selected'),
                name: el.getAttribute('name')
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

        buildDevicePageIdentityChecks(scopeName) {
            const checks = [];
            const viewportMatches = [...document.querySelectorAll(this.selectors.viewport)];
            const viewport = viewportMatches.length === 1 ? viewportMatches[0] : null;
            const pageTexts = this.getPageTextCandidates();
            const productIdentity = this.hasProductIdentityText(pageTexts);
            const sensorText = this.hasSensorText(pageTexts);
            const deviceDefaultText = this.hasDeviceDefaultText(pageTexts);
            const sensorNav = this.resolveSensorNavigation();

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
                `${scopeName}.deviceDefault.text`,
                deviceDefaultText,
                'fatal',
                '画面上の可視テキストまたは document.title から「デバイス (既定グループ)」を確認できること',
                { pageTexts, documentTitle: document.title || '' }
            ));

            checks.push(this.makeCheck(
                `${scopeName}.navigation.sensor.unique`,
                sensorNav.ok,
                'fatal',
                '左ナビまたはナビゲーション内の「センサー」が一意に特定できること',
                sensorNav
            ));

            return { checks, pageTexts, viewport, productIdentity, sensorText, deviceDefaultText, sensorNav };
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

        getHeaderTextFromCell(cell) {
            return this.norm(cell ? cell.textContent : '');
        },

        resolveHeaderContract() {
            const headerInfos = this.getHeaderRowsInfo(null);
            const validHeaderInfos = headerInfos.filter(x => x.hasRequiredHeaders && x.hasCheckboxHeader);
            const target = validHeaderInfos.length === 1 ? validHeaderInfos[0] : null;
            const columnIndexes = {};
            const duplicateHeaders = [];

            if (target) {
                for (const label of this.requiredHeaders) {
                    const indexes = [];
                    target.headers.forEach((text, index) => {
                        if (text === label) indexes.push(index);
                    });

                    if (indexes.length === 1) {
                        columnIndexes[label] = indexes[0];
                    }
                    else {
                        duplicateHeaders.push({ label, indexes });
                    }
                }
            }

            return {
                ok: !!target && duplicateHeaders.length === 0,
                headerRows: headerInfos,
                validHeaderRows: validHeaderInfos,
                target,
                columnIndexes,
                duplicateHeaders
            };
        },

        detectDevicePageIdentity() {
            const identity = this.buildDevicePageIdentityChecks('identity');

            return this.contractResult('scanTargetSyncDevicePageIdentity', identity.checks, {
                pageTexts: identity.pageTexts,
                productIdentity: identity.productIdentity,
                sensorText: identity.sensorText,
                deviceDefaultText: identity.deviceDefaultText,
                sensorNavigation: identity.sensorNav
            });
        },

        validateDevicePageContract() {
            const identity = this.buildDevicePageIdentityChecks('page');
            const checks = [];
            checks.push(this.makeCheck(
                'page.document.ready',
                document.readyState === 'complete',
                'fatal',
                'document.readyState が complete であること',
                { readyState: document.readyState }
            ));
            checks.push(...identity.checks);

            const searchBox = document.querySelector(this.selectors.searchBox);
            const draggableRows = this.getVisibleDraggableRows();
            const totalCount = this.getDeviceListTotalCount();

            checks.push(this.makeCheck(
                'page.searchBox.exists',
                !!searchBox,
                'fatal',
                '検索欄 input#searchBox が存在すること。ただし自動化では検索欄を使用しない。',
                { searchBox: this.elementDebug(searchBox) }
            ));

            checks.push(this.makeCheck(
                'page.deviceCount.readable',
                totalCount.ok && totalCount.value !== null,
                'fatal',
                '画面上の「センサー: <件数>」から一覧件数を一意に取得できること',
                totalCount
            ));

            checks.push(this.makeCheck(
                'page.draggableRows.exists',
                draggableRows.length > 0,
                'fatal',
                'DataTable の表示行が存在すること',
                { rowCount: draggableRows.length }
            ));

            return this.contractResult('scanTargetSyncDevicePage', checks, {
                pageTexts: identity.pageTexts,
                productIdentity: identity.productIdentity,
                sensorText: identity.sensorText,
                deviceDefaultText: identity.deviceDefaultText,
                sensorNavigation: identity.sensorNav.summary,
                totalCount: totalCount.value,
                visibleDraggableRowCount: draggableRows.length
            });
        },

        summarizeOperationScope(scope) {
            if (!scope) return null;

            return {
                name: scope.name,
                kind: scope.kind,
                ok: scope.ok,
                isFixedLeft: scope.isFixedLeft,
                columnCount: scope.columnCount,
                rawRowCount: scope.rawRowCount,
                rowInfoCount: scope.rowInfos ? scope.rowInfos.length : 0,
                rowsWithEndpointCellCount: scope.rowsWithEndpointCellCount,
                rowsWithNonEmptyEndpointCount: scope.rowsWithNonEmptyEndpointCount,
                rowsWithDataIdCount: scope.rowsWithDataIdCount,
                checkboxBadRowCount: scope.checkboxBadRows ? scope.checkboxBadRows.length : 0,
                duplicateKeys: scope.duplicateKeys || [],
                endpointIndex: scope.operationHeader ? scope.operationHeader.endpointIndex : null,
                headerRows: scope.operationHeader ? scope.operationHeader.headerRows.map(x => ({
                    index: x.index,
                    headers: x.headers,
                    hasEndpointHeader: x.hasEndpointHeader,
                    hasCheckboxHeader: x.hasCheckboxHeader,
                    element: this.elementDebug(x.row)
                })) : [],
                root: scope.rootDebug || this.elementDebug(scope.root)
            };
        },

        validateDeviceListContract() {
            const checks = [];
            const header = this.resolveHeaderContract();
            const rowScope = this.resolveDeviceRowScope();
            const selectedScope = rowScope.selected;
            const totalCount = this.getDeviceListTotalCount();
            const rows = selectedScope ? selectedScope.rawRows : [];
            const rowInfos = selectedScope ? selectedScope.rowInfos : [];
            const rawRowCount = rows.length;
            const rowsWithDataId = rowInfos.filter(x => x.dataId);
            const rowsWithEndpoint = rowInfos.filter(x => x.endpoint);
            const identityKeys = rowInfos.map(x => x.dataId + '|' + x.endpoint);
            const duplicateKeys = this.uniqueValues(identityKeys.filter((key, index) => identityKeys.indexOf(key) !== index));
            const scroller = this.findScrollContainer();
            const scrollerContainsRows = !!scroller && (
                this.isDocumentScroller(scroller) ||
                !!scroller.querySelector(this.selectors.draggableRow)
            );
            const checkboxBadRows = rowInfos.filter(x => x.checkboxCandidateCount !== 1);
            const scopeSummaries = rowScope.scopeCandidates.map(x => this.summarizeOperationScope(x));

            checks.push(this.makeCheck(
                'deviceList.fullHeaderRow.unique',
                header.validHeaderRows.length === 1,
                'fatal',
                '全必須ヘッダーを持つ通常一覧ヘッダー行が可視かつ一意であること',
                {
                    headerRowCount: header.headerRows.length,
                    validHeaderRowCount: header.validHeaderRows.length,
                    headers: header.headerRows.map(x => ({
                        index: x.index,
                        headers: x.headers,
                        hasRequiredHeaders: x.hasRequiredHeaders,
                        hasCheckboxHeader: x.hasCheckboxHeader,
                        element: this.elementDebug(x.row)
                    }))
                }
            ));

            checks.push(this.makeCheck(
                'deviceList.requiredHeaders.uniqueInResolvedRow',
                header.ok,
                'fatal',
                '解決済みの通常一覧ヘッダー行で必須列名がそれぞれ一意に存在すること',
                {
                    columnIndexes: header.columnIndexes,
                    duplicateHeaders: header.duplicateHeaders,
                    requiredHeaders: this.requiredHeaders
                }
            ));

            checks.push(this.makeCheck(
                'deviceList.operationScope.unique',
                rowScope.ok,
                'fatal',
                'checkbox操作に使うDOMスコープが一意に解決できること。固定左テーブルが1件だけ有効なら採用し、固定左がない場合は有効候補が1件だけであること。複数候補から列数等で推測採用しない。',
                {
                    selectionReason: rowScope.selectionReason,
                    ambiguousReason: rowScope.ambiguousReason,
                    selectedScope: this.summarizeOperationScope(selectedScope),
                    validScopeCount: rowScope.validScopes.length,
                    scopeCandidateCount: rowScope.scopeCandidates.length,
                    scopes: scopeSummaries
                }
            ));

            checks.push(this.makeCheck(
                'deviceList.rows.exists',
                rawRowCount > 0,
                'fatal',
                '選択済み操作スコープ内に表示中のデバイス一覧行が1件以上存在すること',
                {
                    rawRowCount,
                    selectedScope: selectedScope ? selectedScope.name : null
                }
            ));

            checks.push(this.makeCheck(
                'deviceList.rows.nonEmptyDataId',
                rawRowCount > 0 && rowsWithDataId.length === rawRowCount,
                'fatal',
                '選択済み操作スコープ内の全データ行で data-id が空でないこと',
                {
                    rawRowCount,
                    rowsWithDataIdCount: rowsWithDataId.length,
                    selectedScope: selectedScope ? selectedScope.name : null,
                    rows: rowInfos
                }
            ));

            checks.push(this.makeCheck(
                'deviceList.rows.nonEmptyEndpoint',
                rawRowCount > 0 && rowsWithEndpoint.length === rawRowCount,
                'fatal',
                '選択済み操作スコープ内の全データ行でホスト名が空でないこと',
                {
                    rawRowCount,
                    rowsWithEndpointCount: rowsWithEndpoint.length,
                    selectedScope: selectedScope ? selectedScope.name : null,
                    rows: rowInfos
                }
            ));

            checks.push(this.makeCheck(
                'deviceList.rows.checkbox.unique',
                rawRowCount > 0 && checkboxBadRows.length === 0,
                'fatal',
                '選択済み操作スコープ内の全データ行で選択チェックボックス候補が1件だけであること',
                {
                    badRowCount: checkboxBadRows.length,
                    selectedScope: selectedScope ? selectedScope.name : null,
                    badRows: checkboxBadRows
                }
            ));

            checks.push(this.makeCheck(
                'deviceList.rowIdentity.unique',
                rowScope.ok && duplicateKeys.length === 0,
                'fatal',
                '選択済み操作スコープ内の data-id + ホスト名 が一意であること。通常テーブルと固定左テーブルの重複描画はスコープ解決で除外する。',
                {
                    duplicateKeys,
                    rowCount: rowInfos.length,
                    selectedScope: selectedScope ? selectedScope.name : null,
                    selectedScopeKind: selectedScope ? selectedScope.kind : null
                }
            ));

            checks.push(this.makeCheck(
                'deviceList.totalCount.readable',
                totalCount.ok && totalCount.value !== null,
                'fatal',
                '一覧件数が一意に読めること。件数不明のままスクロール終端だけで正常終了しない。',
                totalCount
            ));

            checks.push(this.makeCheck(
                'deviceList.scroll.container.valid',
                !!scroller && scrollerContainsRows,
                'fatal',
                'デバイス一覧行を含むスクロール領域を解決できること',
                {
                    scroller: this.elementDebug(scroller),
                    containsRows: scrollerContainsRows
                }
            ));

            if (rowScope.ok && selectedScope) {
                this.setPreparedOperationContext(selectedScope, rowScope.selectionReason);
            }

            return this.contractResult('scanTargetSyncDeviceList', checks, {
                rowCount: rowInfos.length,
                totalCount: totalCount.value,
                columnIndexes: header.columnIndexes,
                operationScope: selectedScope ? {
                    name: selectedScope.name,
                    kind: selectedScope.kind,
                    selectionReason: rowScope.selectionReason,
                    endpointIndex: selectedScope.operationHeader.endpointIndex,
                    columnCount: selectedScope.columnCount
                } : null,
                operationScopeCandidates: scopeSummaries,
                preparedOperationContext: this.summarizePreparedOperationContext(this.getPreparedOperationContext()),
                scrollTop: scroller ? this.getScrollTop(scroller) : null
            });
        },

        getSearchManualScanStartMenuItems() {
            return [...document.querySelectorAll(this.selectors.menuItem)]
                .filter(el => this.norm(el.textContent) === '手動スキャンの開始')
                .map(el => {
                    const root = el.closest('[class*="ui-dropdown"]');
                    return {
                        el,
                        root,
                        text: this.norm(el.textContent),
                        rootText: this.norm(root ? root.textContent : ''),
                        itemDisabled: this.isDisabled(el),
                        rootDisabled: this.isDisabled(root)
                    };
                })
                .filter(x => x.rootText.indexOf('端末共通') >= 0 || x.rootText.indexOf('手動スキャンの開始') >= 0);
        },

        validatePostSelectionContract() {
            const checks = [];
            const selectedRows = this.findDeviceRowsInfo().filter(x => x.selected);
            const manualScanStartItems = this.getSearchManualScanStartMenuItems();
            const enabledItems = manualScanStartItems.filter(x => !x.itemDisabled && !x.rootDisabled);

            checks.push(this.makeCheck(
                'postSelection.selectedRows.exists',
                selectedRows.length > 0,
                'warning',
                '表示中DOM上で選択行を確認できること。仮想スクロールで選択済み行が表示範囲外にある場合は warning とし、各行クリック直後の選択確認と手動スキャンメニュー有効化を主契約とする。',
                { selectedRowCount: selectedRows.length, selectedRows }
            ));

            checks.push(this.makeCheck(
                'postSelection.manualScanStart.unique',
                manualScanStartItems.length === 1,
                'fatal',
                '「手動スキャンの開始」メニュー項目が一意に解決できること',
                {
                    candidateCount: manualScanStartItems.length,
                    candidates: manualScanStartItems.map(x => ({
                        item: this.elementDebug(x.el),
                        root: this.elementDebug(x.root),
                        rootText: x.rootText,
                        itemDisabled: x.itemDisabled,
                        rootDisabled: x.rootDisabled
                    }))
                }
            ));

            checks.push(this.makeCheck(
                'postSelection.manualScanStart.enabled',
                manualScanStartItems.length === 1 && enabledItems.length === 1,
                'fatal',
                'チェック後に 端末共通メニューの「手動スキャンの開始」が有効化されていること。ただしこのスクリプトではクリックしない。',
                {
                    enabledCount: enabledItems.length,
                    candidates: manualScanStartItems.map(x => ({
                        item: this.elementDebug(x.el),
                        root: this.elementDebug(x.root),
                        rootText: x.rootText,
                        itemDisabled: x.itemDisabled,
                        rootDisabled: x.rootDisabled
                    }))
                }
            ));

            return this.contractResult('scanTargetSyncPostSelection', checks, {
                selectedRowCount: selectedRows.length,
                manualScanStartCandidateCount: manualScanStartItems.length,
                enabledManualScanStartCount: enabledItems.length
            });
        },
    };

    root.__ScanTargetSyncDomHelperParts = root.__ScanTargetSyncDomHelperParts || [];
    root.__ScanTargetSyncDomHelperParts.push(part);

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = part;
    }

    return true;
})(typeof window !== 'undefined' ? window : globalThis);

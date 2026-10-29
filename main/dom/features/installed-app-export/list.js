(function registerInstalledAppExportListPart(root) {
    const part = {
        getHeaderRows() {
            const fixedHeaderRow = document.querySelector(this.selectors.fixedHeaderRow);
            const mainHeaderRow = document.querySelector(this.selectors.mainHeaderRow);

            return {
                fixedHeaderRow,
                mainHeaderRow,
                visibleRows: [fixedHeaderRow, mainHeaderRow].filter(el => this.isVisible(el))
            };
        },

        findSelectorHeader() {
            const { fixedHeaderRow, mainHeaderRow } = this.getHeaderRows();

            return (fixedHeaderRow ? fixedHeaderRow.querySelector(this.selectors.selectorHeader) : null) ||
                   (mainHeaderRow ? mainHeaderRow.querySelector(this.selectors.selectorHeader) : null) ||
                   document.querySelector(this.selectors.selectorHeader);
        },

        getHeaderTextCandidates(el) {
            if (!el) return [];

            const values = [];
            const ariaLabel = this.norm(el.getAttribute('aria-label'));
            const title = this.norm(el.getAttribute('title'));
            const headerTextEl = el.querySelector('.ui-iggrid-headertext, span.ui-iggrid-headertext');
            const headerText = this.norm(headerTextEl ? headerTextEl.textContent : '');
            const directText = this.norm(el.textContent);

            values.push(ariaLabel, title, headerText, directText);

            return [...new Set(values.filter(Boolean))];
        },

        getHeaderSide(el) {
            if (!el) return '';
            if (el.closest('#asset-grid_headers_fixed')) return 'fixed';
            if (el.closest('#asset-grid_headers')) return 'main';
            return 'unknown';
        },

        getHeaderCandidatesByText(label) {
            const { fixedHeaderRow, mainHeaderRow } = this.getHeaderRows();
            const candidates = [];

            // 端末名列の所在は固定列側・通常列側のどちらにもなり得る。
            // 契約の起点は固定IDではなく、業務列名「端末名」の一意性とする。
            if (fixedHeaderRow) {
                candidates.push(...fixedHeaderRow.querySelectorAll('th[id]'));
            }

            if (mainHeaderRow) {
                candidates.push(...mainHeaderRow.querySelectorAll('th[id]'));
            }

            const container = document.querySelector(this.selectors.gridContainer) || document;
            candidates.push(...container.querySelectorAll('th[id]'));

            return this.uniqueElements(candidates)
                .map(el => {
                    const texts = this.getHeaderTextCandidates(el);
                    const matchesLabel = texts.includes(label);

                    return {
                        el,
                        id: el.id || '',
                        text: texts[0] || '',
                        texts,
                        matchesLabel,
                        visible: this.isVisible(el),
                        side: this.getHeaderSide(el)
                    };
                });
        },

        findAssetNameHeaderCandidates() {
            return this.getHeaderCandidatesByText('端末名')
                .filter(x => x.matchesLabel || x.id === 'asset-grid_asset_name');
        },

        cssEscapeIdent(value) {
            if (window.CSS && typeof window.CSS.escape === 'function') {
                return window.CSS.escape(value);
            }

            return String(value).replace(/[^a-zA-Z0-9_-]/g, ch => '\\' + ch);
        },

        resolveAssetNameColumn() {
            const candidates = this.findAssetNameHeaderCandidates();
            const visibleCandidates = candidates.filter(x => x.visible);
            const validCandidates = visibleCandidates.filter(x => x.matchesLabel && !!x.id);
            const target = validCandidates.length === 1 ? validCandidates[0] : null;
            const columnId = target ? target.id : '';
            const cellSelector = columnId
                ? 'td[aria-describedby="' + this.cssEscapeIdent(columnId) + '"]'
                : '';

            return {
                ok: !!target,
                columnId,
                cellSelector,
                header: target ? target.el : null,
                candidates,
                visibleCandidates,
                validCandidates
            };
        },

        getAssetNameCellFromRow(row) {
            if (!row) return null;

            const column = this.resolveAssetNameColumn();

            if (!column.ok || !column.cellSelector) {
                return null;
            }

            return row.querySelector(column.cellSelector);
        },

        validateAssetListContract() {
            const checks = [];
            const { fixedHeaderRow, mainHeaderRow, visibleRows } = this.getHeaderRows();
            const selectorHeader = this.findSelectorHeader();
            const selectorCheckbox = selectorHeader
                ? selectorHeader.querySelector('#asset-grid_all_select input[type="checkbox"]')
                : null;
            const assetNameColumn = this.resolveAssetNameColumn();
            const nameHeaderCandidates = assetNameColumn.candidates;
            const visibleNameHeaders = assetNameColumn.visibleCandidates;
            const validNameHeaders = assetNameColumn.validCandidates;
            const rowScope = this.resolveAssetRowScope();
            const targetScope = rowScope.target;
            const rawRows = targetScope ? targetScope.rawRows : [];
            const rowsWithNameCell = targetScope ? targetScope.rowsWithNameCell : [];
            const rowsWithNonEmptyAssetName = targetScope ? targetScope.rowsWithNonEmptyAssetName : [];
            const rowInfos = this.findAssetRowsInfo();
            const rowsWithNonEmptyDataId = rowInfos;
            const identityKeys = rowInfos.map(x => x.dataId + '|' + x.assetName);
            const duplicateKeys = [...new Set(identityKeys.filter((key, index) => identityKeys.indexOf(key) !== index))];
            const scroller = this.findScrollContainer();
            const scrollerContainsRows = !!scroller && (
                scroller === document.scrollingElement ||
                scroller === document.documentElement ||
                scroller === document.body ||
                !!scroller.querySelector(`${this.selectors.mainGrid} tbody tr[data-id], ${this.selectors.fixedGrid} tbody tr[data-id]`)
            );
            const totalCount = this.getAssetListTotalCount();

            checks.push(this.makeCheck(
                'assetList.headerRow.visible',
                visibleRows.length > 0,
                'fatal',
                '固定列側または通常列側のヘッダー行が可視であること',
                {
                    fixedHeaderVisible: this.isVisible(fixedHeaderRow),
                    mainHeaderVisible: this.isVisible(mainHeaderRow)
                }
            ));

            checks.push(this.makeCheck(
                'assetList.selectorColumn.exists',
                !!selectorHeader && this.isVisible(selectorHeader) && !!selectorCheckbox,
                'fatal',
                '選択列ヘッダーと全選択チェックボックスが存在すること',
                {
                    selectorHeader: this.elementDebug(selectorHeader),
                    selectorCheckbox: this.elementDebug(selectorCheckbox)
                }
            ));

            checks.push(this.makeCheck(
                'assetList.nameHeader.unique',
                validNameHeaders.length === 1,
                'fatal',
                '端末名ヘッダーが可視かつ一意で、文言が「端末名」であり、対応セル解決用の id を持つこと',
                {
                    candidateCount: nameHeaderCandidates.length,
                    visibleCount: visibleNameHeaders.length,
                    validCount: validNameHeaders.length,
                    resolvedColumnId: assetNameColumn.columnId,
                    candidates: nameHeaderCandidates.map(x => ({
                        id: x.id,
                        text: x.text,
                        texts: x.texts,
                        matchesLabel: x.matchesLabel,
                        side: x.side,
                        visible: x.visible,
                        element: this.elementDebug(x.el)
                    }))
                }
            ));

            checks.push(this.makeCheck(
                'assetList.rowScope.unique',
                rowScope.validScopes.length === 1,
                'fatal',
                '処理対象の一覧スコープが一意に決定できること。mainGrid/fixedGrid の複数候補や0候補を先頭採用しない。',
                {
                    reason: rowScope.reason,
                    validScopeCount: rowScope.validScopes.length,
                    validScopes: rowScope.validScopes.map(x => x.name),
                    operationScopes: rowScope.operationScopes.map(x => ({
                        name: x.name,
                        rawRowCount: x.rawRows.length,
                        rowsWithNameCellCount: x.rowsWithNameCell.length,
                        rowsWithNonEmptyAssetNameCount: x.rowsWithNonEmptyAssetName.length
                    })),
                    diagnosticScopes: rowScope.scopes.map(x => ({
                        name: x.name,
                        rawRowCount: x.rawRows.length,
                        rowsWithNameCellCount: x.rowsWithNameCell.length,
                        rowsWithNonEmptyAssetNameCount: x.rowsWithNonEmptyAssetName.length
                    }))
                }
            ));

            checks.push(this.makeCheck(
                'assetList.rawRows.exists',
                rawRows.length > 0,
                'fatal',
                '処理対象スコープ内に tr[data-id] の生行が1件以上存在すること',
                {
                    scope: targetScope ? targetScope.name : null,
                    rawRowCount: rawRows.length,
                    scopes: rowScope.scopes.map(x => ({
                        name: x.name,
                        rawRowCount: x.rawRows.length,
                        rowsWithNameCellCount: x.rowsWithNameCell.length,
                        rowsWithNonEmptyAssetNameCount: x.rowsWithNonEmptyAssetName.length
                    }))
                }
            ));

            checks.push(this.makeCheck(
                'assetList.nameCell.available',
                rawRows.length > 0 && rawRows.length === rowsWithNameCell.length,
                'fatal',
                '処理対象スコープ内の全データ行で、解決済み端末名列セルを取得できること',
                {
                    rawRowCount: rawRows.length,
                    rowsWithNameCellCount: rowsWithNameCell.length,
                    missingCount: Math.max(rawRows.length - rowsWithNameCell.length, 0),
                    scope: targetScope ? targetScope.name : null
                }
            ));

            checks.push(this.makeCheck(
                'assetList.assetName.nonEmpty',
                rowsWithNameCell.length > 0 && rowsWithNameCell.length === rowsWithNonEmptyAssetName.length,
                'fatal',
                '処理対象スコープ内の全データ行で、端末名が空でないこと',
                {
                    rowsWithNameCellCount: rowsWithNameCell.length,
                    rowsWithNonEmptyAssetNameCount: rowsWithNonEmptyAssetName.length,
                    emptyNameCount: Math.max(rowsWithNameCell.length - rowsWithNonEmptyAssetName.length, 0),
                    scope: targetScope ? targetScope.name : null
                }
            ));

            checks.push(this.makeCheck(
                'assetList.dataId.nonEmpty',
                rowsWithNonEmptyAssetName.length > 0 && rowsWithNonEmptyAssetName.length === rowsWithNonEmptyDataId.length,
                'fatal',
                '処理対象スコープ内の全データ行で、data-id が空でないこと',
                {
                    rowsWithNonEmptyAssetNameCount: rowsWithNonEmptyAssetName.length,
                    rowsWithNonEmptyDataIdCount: rowsWithNonEmptyDataId.length,
                    emptyDataIdCount: Math.max(rowsWithNonEmptyAssetName.length - rowsWithNonEmptyDataId.length, 0),
                    scope: targetScope ? targetScope.name : null
                }
            ));

            checks.push(this.makeCheck(
                'assetList.rows.exists',
                rowInfos.length > 0,
                'fatal',
                '処理対象の端末一覧行が1件以上存在すること',
                {
                    validRowCount: rowInfos.length,
                    scope: targetScope ? targetScope.name : null
                }
            ));

            checks.push(this.makeCheck(
                'assetList.rowIdentity.unique',
                duplicateKeys.length === 0,
                'fatal',
                '表示中DOM上の data-id + 端末名 が一意であること',
                {
                    duplicateKeys,
                    rowCount: rowInfos.length
                }
            ));

            checks.push(this.makeCheck(
                'scroll.container.valid',
                !!scroller && scrollerContainsRows,
                'fatal',
                '端末一覧行を含むスクロール領域を解決できること。totalCount を必須契約にしたため、走査完了の根拠としてスクロール領域も必須とする。',
                {
                    scroller: this.elementDebug(scroller),
                    containsRows: scrollerContainsRows
                }
            ));

            checks.push(this.makeCheck(
                'assetList.totalCount.readable',
                totalCount !== null,
                'fatal',
                '一覧件数が読めること。件数不明のままスクロール終端だけで正常終了しない。',
                { totalCount }
            ));

            return this.contractResult('assetList', checks, {
                rowCount: rowInfos.length,
                rawRowCount: rawRows.length,
                totalCount,
                assetNameColumnId: assetNameColumn.columnId,
                rowScope: targetScope ? targetScope.name : null,
                rowScopeReason: rowScope.reason,
                validRowScopeCount: rowScope.validScopes.length
            });
        },

        parseCountText(text) {
            const normalized = this.norm(text).replace(/,/g, '');
            const slash = normalized.match(/\/\s*(\d+)\s*(?:件)?\s*$/);
            const total = normalized.match(/(?:全|合計)\s*(\d+)\s*(?:件)?/);
            const simple = normalized.match(/^(\d+)\s*(?:件)?$/);

            if (slash) return Number(slash[1]);
            if (total) return Number(total[1]);
            if (simple) return Number(simple[1]);

            const numbers = normalized.match(/\d+/g) || [];

            if (numbers.length === 1) {
                return Number(numbers[0]);
            }

            return null;
        },

        getAssetListTotalCount() {
            const countEl = document.querySelector('[ng-bind="assetList.totalCount"]');
            const text = this.norm(countEl ? countEl.textContent : '');
            return this.parseCountText(text);
        },

        buildAssetRowScope(name, root, column) {
            const rawRows = root
                ? this.uniqueElements([...root.querySelectorAll('tbody tr[data-id]')])
                : [];
            const rowsWithNameCell = column && column.ok && column.cellSelector
                ? rawRows.filter(row => !!row.querySelector(column.cellSelector))
                : [];
            const rowsWithNonEmptyAssetName = rowsWithNameCell
                .filter(row => {
                    const nameCell = row.querySelector(column.cellSelector);
                    return !!nameCell && !!this.norm(nameCell.textContent);
                });

            return {
                name,
                root,
                rawRows,
                rowsWithNameCell,
                rowsWithNonEmptyAssetName
            };
        },

        resolveAssetRowScope() {
            const column = this.resolveAssetNameColumn();
            const mainGrid = document.querySelector(this.selectors.mainGrid);
            const fixedGrid = document.querySelector(this.selectors.fixedGrid);
            const gridContainer = document.querySelector(this.selectors.gridContainer) || document;
            const operationScopes = [
                this.buildAssetRowScope('mainGrid', mainGrid, column),
                this.buildAssetRowScope('fixedGrid', fixedGrid, column)
            ];
            const diagnosticScopes = [
                ...operationScopes,
                this.buildAssetRowScope('gridContainer', gridContainer, column)
            ];
            const validScopes = operationScopes.filter(x =>
                x.rawRows.length > 0 &&
                x.rawRows.length === x.rowsWithNameCell.length &&
                x.rawRows.length === x.rowsWithNonEmptyAssetName.length
            );
            const target = validScopes.length === 1 ? validScopes[0] : null;
            const reason = validScopes.length === 1
                ? 'unique_operational_scope'
                : (validScopes.length === 0 ? 'no_valid_operational_scope' : 'ambiguous_operational_scope');

            return {
                ok: !!target,
                column,
                scopes: diagnosticScopes,
                operationScopes,
                validScopes,
                target,
                reason
            };
        },

        findAssetRows() {
            const rowScope = this.resolveAssetRowScope();
            return rowScope.target ? rowScope.target.rowsWithNonEmptyAssetName : [];
        },

        getAssetNameFromRow(row) {
            const nameCell = this.getAssetNameCellFromRow(row);
            return nameCell ? this.norm(nameCell.textContent) : '';
        },

        getRowInfoFromRow(row, index) {
            return {
                dataId: row.getAttribute('data-id'),
                assetName: this.getAssetNameFromRow(row),
                index,
                ariaSelected: row.getAttribute('aria-selected'),
                selectedRowClass: row.classList.contains('selected-row')
            };
        },

        findAssetRowsInfo() {
            return this.findAssetRows()
                .map((row, index) => this.getRowInfoFromRow(row, index))
                .filter(x => x.dataId && x.assetName);
        },

        getSelectedAssetRow() {
            const selectedRows = this.findAssetRows()
                .filter(row => row.getAttribute('aria-selected') === 'true');

            if (selectedRows.length !== 1) {
                return {
                    ok: false,
                    count: selectedRows.length,
                    rows: selectedRows.map((row, index) => this.getRowInfoFromRow(row, index))
                };
            }

            const row = selectedRows[0];
            return {
                ok: true,
                count: 1,
                ...this.getRowInfoFromRow(row, 0)
            };
        },

        scrollRowIntoView(row) {
            if (!row) return;

            const scroller = this.findScrollContainer();

            try {
                if (
                    scroller &&
                    scroller !== document.scrollingElement &&
                    scroller !== document.documentElement &&
                    scroller !== document.body
                ) {
                    const targetTop = Math.max(
                        row.offsetTop - Math.floor(scroller.clientHeight / 2) + Math.floor(row.offsetHeight / 2),
                        0
                    );

                    this.setScrollTop(scroller, targetTop);
                }
            }
            catch {
                // scrollIntoView 側で補完する。
            }

            row.scrollIntoView({
                block: 'center',
                inline: 'nearest'
            });
        },

        resolveAssetRow(dataId, assetName) {
            const rows = this.findAssetRows()
                .filter(row => {
                    return row.getAttribute('data-id') === dataId &&
                           this.getAssetNameFromRow(row) === assetName;
                });
            const row = rows.length === 1 ? rows[0] : null;
            const nameCell = row ? this.getAssetNameCellFromRow(row) : null;
            const cellVisible = !!nameCell && this.isVisible(nameCell);
            const column = this.resolveAssetNameColumn();

            return {
                ok: rows.length === 1 && cellVisible,
                row,
                nameCell,
                candidateCount: rows.length,
                candidates: rows.map((candidate, index) => this.getRowInfoFromRow(candidate, index)),
                cellVisible,
                columnId: column ? column.columnId : '',
                expected: { dataId, assetName }
            };
        },

        clickResolvedAssetNameCell(resolved) {
            if (!resolved || !resolved.ok || !resolved.row || !resolved.nameCell) {
                throw new Error('clickResolvedAssetNameCell: resolved row/cell is invalid');
            }

            this.scrollRowIntoView(resolved.row);
            this.clickElement(resolved.nameCell);

            return {
                ok: true,
                action: 'click-asset-name-cell',
                ...this.getRowInfoFromRow(resolved.row, 0)
            };
        },

        clickAssetNameCell(dataId, assetName) {
            const resolved = this.resolveAssetRow(dataId, assetName);

            if (resolved.candidateCount !== 1) {
                throw new Error(
                    '対象端末行が一意に決まりません。dataId=' +
                    dataId +
                    ' assetName=' +
                    assetName +
                    ' count=' +
                    resolved.candidateCount
                );
            }

            if (!resolved.nameCell || !resolved.cellVisible) {
                throw new Error(
                    '端末名セルが見つからない、または表示されていません。dataId=' +
                    dataId +
                    ' columnId=' +
                    resolved.columnId
                );
            }

            return this.clickResolvedAssetNameCell(resolved);
        },

        findScrollContainer() {
            const selectorCandidates = [
                // 今回の画面では通常行の縦スクロールはこちら。
                '#asset-grid_scroll',

                // igGrid の通常スクロール領域。
                '#asset-grid_container .ui-iggrid-scrolldiv',

                // data-scroll=true のうち、通常グリッドを含むもの。
                '#asset-grid_container [data-scroll="true"]',

                // 端末名列は固定列側にだけ描画される構成もあるため、業務列名から一意解決する。
                '#asset-grid_fixedBodyContainer',
                '#asset-grid_container .igscroll-touchscrollable'
            ];

            const candidates = [];

            for (const selector of selectorCandidates) {
                const el = document.querySelector(selector);

                if (
                    el &&
                    this.isVisible(el) &&
                    el.scrollHeight > el.clientHeight + 10
                ) {
                    candidates.push(el);
                }
            }

            const genericCandidates = [...document.querySelectorAll('div, main, section')]
                .filter(el => {
                    if (!this.isVisible(el)) return false;

                    // 通常グリッド側または固定グリッド側のデータ行を含むスクロール候補を拾う。
                    const hasMainRows = !!el.querySelector(`${this.selectors.mainGrid} tbody tr[data-id]`);
                    const hasFixedRows = !!el.querySelector(`${this.selectors.fixedGrid} tbody tr[data-id]`);

                    if (!hasMainRows && !hasFixedRows) return false;

                    return el.scrollHeight > el.clientHeight + 10;
                });

            candidates.push(...genericCandidates);

            if (candidates.length > 0) {
                candidates.sort((a, b) => {
                    // 通常グリッドのスクロール領域を最優先。
                    if (a.matches && a.matches('#asset-grid_scroll')) return -1;
                    if (b.matches && b.matches('#asset-grid_scroll')) return 1;

                    const aScrollable = a.scrollHeight - a.clientHeight;
                    const bScrollable = b.scrollHeight - b.clientHeight;

                    return bScrollable - aScrollable;
                });

                return candidates[0];
            }

            return document.scrollingElement || document.documentElement;
        },

        getScrollTop(scroller) {
            if (
                scroller === document.scrollingElement ||
                scroller === document.documentElement ||
                scroller === document.body
            ) {
                return window.scrollY ||
                       document.documentElement.scrollTop ||
                       document.body.scrollTop ||
                       0;
            }

            return scroller.scrollTop;
        },

        setScrollTop(scroller, value) {
            if (
                scroller === document.scrollingElement ||
                scroller === document.documentElement ||
                scroller === document.body
            ) {
                window.scrollTo(0, value);
            } else {
                scroller.scrollTop = value;
                scroller.dispatchEvent(new Event('scroll', { bubbles: true }));
            }
        },

        scrollByAmount(scroller, amount) {
            const before = this.getScrollTop(scroller);
            this.setScrollTop(scroller, before + amount);
            const after = this.getScrollTop(scroller);

            return {
                before,
                after,
                moved: after !== before,
                amount,
                clientHeight: scroller.clientHeight || window.innerHeight,
                scrollHeight: scroller.scrollHeight || document.documentElement.scrollHeight
            };
        },

        scrollDown() {
            const scroller = this.findScrollContainer();
            const amount =
                scroller && scroller.clientHeight
                    ? Math.max(Math.floor(scroller.clientHeight * 0.75), 300)
                    : 500;

            return this.scrollByAmount(scroller, amount);
        },

        scrollToTop() {
            const scroller = this.findScrollContainer();
            this.setScrollTop(scroller, 0);

            return {
                ok: true,
                scrollTop: this.getScrollTop(scroller)
            };
        },

    };

    root.__InstalledAppExportDomHelperParts = root.__InstalledAppExportDomHelperParts || [];
    root.__InstalledAppExportDomHelperParts.push(part);

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = part;
    }

    return true;
})(typeof window !== 'undefined' ? window : globalThis);

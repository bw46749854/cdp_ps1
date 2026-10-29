(function registerScanTargetSyncListPart(root) {
    const part = {
        getDraggableRows() {
            return [...document.querySelectorAll(this.selectors.draggableRow)];
        },

        getVisibleDraggableRows() {
            return this.getDraggableRows().filter(row => this.isVisible(row));
        },

        getDirectCells(row) {
            if (!row) return [];

            return [...row.children].filter(child => {
                const cls = typeof child.className === 'string' ? child.className : '';
                return cls.indexOf('DataTable__header') >= 0 ||
                       cls.indexOf('DataTable__cell') >= 0;
            });
        },

        isDataTableRoot(el) {
            if (!el) return false;
            const cls = typeof el.className === 'string' ? el.className : '';

            // table-area / table-wrapper ではなく、個別の描画テーブル単位をスコープ候補にする。
            // 実画面では通常テーブルと固定左テーブルが同一 data-id を重複描画するため、
            // 一覧全体コンテナをそのまま処理対象にしてはいけない。
            return cls.indexOf('DataTable__table--') >= 0;
        },

        findDataTableRoot(el) {
            let current = el;

            while (current && current !== document.documentElement) {
                if (this.isDataTableRoot(current)) {
                    return current;
                }

                current = current.parentElement;
            }

            return null;
        },

        getScopeKind(root) {
            const cls = typeof root?.className === 'string' ? root.className : '';

            if (cls.indexOf('DataTable__fixed-left') >= 0) {
                return 'fixedLeftTable';
            }

            return 'mainTable';
        },

        getTableScopeRoots() {
            const roots = this.uniqueElements(
                this.getVisibleDraggableRows()
                    .map(row => this.findDataTableRoot(row))
                    .filter(Boolean)
            );

            return roots.map((root, index) => ({
                name: this.getScopeKind(root) + '#' + index,
                kind: this.getScopeKind(root),
                root,
                index,
                className: typeof root.className === 'string' ? root.className : ''
            }));
        },

        getHeaderRowsInfo(root) {
            const rowSource = root
                ? [...root.querySelectorAll(this.selectors.draggableRow)].filter(row => this.isVisible(row))
                : this.getVisibleDraggableRows();

            return rowSource
                .filter(row => !row.hasAttribute('data-id'))
                .map((row, index) => {
                    const cells = this.getDirectCells(row);
                    const headers = cells.map(cell => this.getHeaderTextFromCell(cell));
                    const nonEmptyHeaders = headers.filter(Boolean);

                    return {
                        row,
                        index,
                        cells,
                        headers,
                        nonEmptyHeaders,
                        text: this.norm(row.textContent),
                        hasRequiredHeaders: this.requiredHeaders.every(label => nonEmptyHeaders.indexOf(label) >= 0),
                        hasEndpointHeader: nonEmptyHeaders.indexOf('ホスト名') >= 0,
                        hasCheckboxHeader: cells.length > 0 && !!cells[0].querySelector('input[type="checkbox"]')
                    };
                });
        },

        resolveOperationHeaderContract(scope) {
            const headerInfos = this.getHeaderRowsInfo(scope ? scope.root : null);
            const validHeaderInfos = headerInfos.filter(x => x.hasEndpointHeader && x.hasCheckboxHeader);
            const target = validHeaderInfos.length === 1 ? validHeaderInfos[0] : null;
            const endpointIndexes = [];

            if (target) {
                target.headers.forEach((text, index) => {
                    if (text === 'ホスト名') endpointIndexes.push(index);
                });
            }

            return {
                ok: !!target && endpointIndexes.length === 1,
                headerRows: headerInfos,
                validHeaderRows: validHeaderInfos,
                target,
                endpointIndex: endpointIndexes.length === 1 ? endpointIndexes[0] : null,
                endpointIndexes
            };
        },

        getRowsInScope(scope) {
            if (!scope || !scope.root) return [];

            return [...scope.root.querySelectorAll(this.selectors.draggableRow)]
                .filter(row => this.isVisible(row))
                .filter(row => row.hasAttribute('data-id'));
        },

        getCheckboxCandidatesFromRow(row) {
            if (!row) return [];

            const cells = this.getDirectCells(row);
            const selectorCell = cells.length > 0 ? cells[0] : row;

            return [...selectorCell.querySelectorAll('label')]
                .map(label => ({
                    label,
                    input: label.querySelector('input[type="checkbox"]')
                }))
                .filter(x => x.input);
        },

        getRowInfoFromRow(row, index, scopeResolution) {
            const resolvedScope = scopeResolution || {
                selected: this.getPreparedOperationContext()
            };
            const operationHeader = resolvedScope.selected ? resolvedScope.selected.operationHeader : null;
            const cells = this.getDirectCells(row);
            const endpointIndex = operationHeader && operationHeader.ok ? operationHeader.endpointIndex : 1;
            const endpoint = cells.length > endpointIndex ? this.norm(cells[endpointIndex].textContent) : '';
            const checkboxCandidates = this.getCheckboxCandidatesFromRow(row);
            const input = checkboxCandidates.length === 1 ? checkboxCandidates[0].input : null;
            const selected = this.isRowSelected(row);
            const checked = input ? input.checked === true : null;

            return {
                dataId: row.getAttribute('data-id') || '',
                endpoint,
                // ループ中の行情報は状態同期に必要な最小項目に限定する。
                // status/user はCSV側に保持しており、ここで全ヘッダー契約を再解決しない。
                status: '',
                user: '',
                index,
                text: this.norm(row.textContent),
                ariaSelected: row.getAttribute('aria-selected') || '',
                selected,
                effectiveChecked: selected || checked === true,
                checkboxCandidateCount: checkboxCandidates.length,
                checkboxChecked: checked,
                checkboxDisabled: input ? this.isDisabled(input) : null,
                rowClassName: typeof row.className === 'string' ? row.className : '',
                scopeName: resolvedScope.selected ? resolvedScope.selected.name : '',
                scopeKind: resolvedScope.selected ? resolvedScope.selected.kind : ''
            };
        },

        buildOperationScopeCandidate(scope) {
            const operationHeader = this.resolveOperationHeaderContract(scope);
            const rawRows = this.getRowsInScope(scope);
            const endpointIndex = operationHeader.ok ? operationHeader.endpointIndex : null;
            const rowsWithEndpointCell = endpointIndex !== null
                ? rawRows.filter(row => this.getDirectCells(row).length > endpointIndex)
                : [];
            const rowsWithNonEmptyEndpoint = endpointIndex !== null
                ? rowsWithEndpointCell.filter(row => this.norm(this.getDirectCells(row)[endpointIndex].textContent))
                : [];
            const rowInfos = rowsWithNonEmptyEndpoint.map((row, index) => this.getRowInfoFromRow(row, index, {
                selected: {
                    ...scope,
                    operationHeader
                }
            }));
            const rowsWithDataId = rowInfos.filter(x => x.dataId);
            const checkboxBadRows = rowInfos.filter(x => x.checkboxCandidateCount !== 1);
            const identityKeys = rowInfos.map(x => x.dataId + '|' + x.endpoint);
            const duplicateKeys = this.uniqueValues(identityKeys.filter((key, index) => identityKeys.indexOf(key) !== index));
            const columnCount = operationHeader.target ? operationHeader.target.headers.length : null;

            const ok = operationHeader.ok &&
                       rawRows.length > 0 &&
                       rowsWithEndpointCell.length === rawRows.length &&
                       rowsWithNonEmptyEndpoint.length === rawRows.length &&
                       rowsWithDataId.length === rawRows.length &&
                       checkboxBadRows.length === 0 &&
                       duplicateKeys.length === 0;

            return {
                ...scope,
                operationHeader,
                rawRows,
                rowInfos,
                rawRowCount: rawRows.length,
                rowsWithEndpointCellCount: rowsWithEndpointCell.length,
                rowsWithNonEmptyEndpointCount: rowsWithNonEmptyEndpoint.length,
                rowsWithDataIdCount: rowsWithDataId.length,
                checkboxBadRows,
                duplicateKeys,
                columnCount,
                ok,
                isFixedLeft: scope.kind === 'fixedLeftTable',
                rootDebug: this.elementDebug(scope.root)
            };
        },

        resolveDeviceRowScope() {
            const scopeCandidates = this.getTableScopeRoots().map(scope => this.buildOperationScopeCandidate(scope));
            const validScopes = scopeCandidates.filter(x => x.ok);
            let selected = null;
            let selectionReason = '';
            let ambiguousReason = '';

            const fixedLeftScopes = validScopes.filter(x => x.isFixedLeft);

            if (fixedLeftScopes.length === 1) {
                selected = fixedLeftScopes[0];
                selectionReason = 'valid_fixed_left_scope';
            }
            else if (fixedLeftScopes.length > 1) {
                ambiguousReason = 'multiple_valid_fixed_left_scopes';
            }
            else if (validScopes.length === 1) {
                selected = validScopes[0];
                selectionReason = 'single_valid_scope';
            }
            else if (validScopes.length > 1) {
                ambiguousReason = 'multiple_valid_operation_scopes_without_unique_fixed_left';
            }
            else {
                ambiguousReason = 'no_valid_operation_scope';
            }

            return {
                ok: !!selected,
                selected,
                selectionReason,
                ambiguousReason,
                scopeCandidates,
                validScopes
            };
        },

        findDeviceRows() {
            const context = this.getPreparedOperationContext();

            if (!context) {
                return [];
            }

            return [...context.root.querySelectorAll(this.selectors.draggableRow)]
                .filter(row => this.isVisible(row))
                .filter(row => row.hasAttribute('data-id'));
        },

        findDeviceRowsInfo() {
            const context = this.getPreparedOperationContext();

            if (!context) {
                return [];
            }

            return this.findDeviceRows().map((row, index) => this.getRowInfoFromRow(row, index, {
                selected: context
            }));
        },

        isRowSelected(row) {
            if (!row) return false;

            const cls = typeof row.className === 'string' ? row.className : '';
            const checkboxCandidates = this.getCheckboxCandidatesFromRow(row);
            const checked = checkboxCandidates.some(x => x.input && x.input.checked === true);

            const classNames = cls.split(/\s+/).filter(Boolean);
            const hasKnownActiveClass = classNames.some(name =>
                name === 'tr-active' ||
                name.indexOf('tr-active--') >= 0 ||
                name.indexOf('__tr-active') >= 0
            );

            return row.getAttribute('aria-selected') === 'true' ||
                   checked ||
                   hasKnownActiveClass;
        },

        findRowsByEndpoint(endpoint) {
            const normalizedEndpoint = this.norm(endpoint);
            const context = this.getPreparedOperationContext();

            if (!context) {
                return [];
            }

            return this.findDeviceRows()
                .map((row, index) => ({ row, info: this.getRowInfoFromRow(row, index, { selected: context }) }))
                .filter(x => x.info.endpoint === normalizedEndpoint);
        },

        isDocumentScroller(scroller) {
            return scroller === document.scrollingElement ||
                   scroller === document.documentElement ||
                   scroller === document.body;
        },

        findScrollContainer() {
            const rowSelector = this.selectors.draggableRow;
            const candidates = [...document.querySelectorAll('div, main, section')]
                .filter(el => {
                    if (!this.isVisible(el)) return false;
                    if (!el.querySelector(rowSelector)) return false;
                    return el.scrollHeight > el.clientHeight + 50;
                })
                .sort((a, b) => {
                    const aScrollable = a.scrollHeight - a.clientHeight;
                    const bScrollable = b.scrollHeight - b.clientHeight;
                    return bScrollable - aScrollable;
                });

            if (candidates.length > 0) {
                return candidates[0];
            }

            return document.scrollingElement || document.documentElement;
        },

        getScrollTop(scroller) {
            if (!scroller) return 0;

            if (this.isDocumentScroller(scroller)) {
                return window.scrollY ||
                       document.documentElement.scrollTop ||
                       document.body.scrollTop ||
                       0;
            }

            return scroller.scrollTop;
        },

        dispatchScrollEvent(scroller) {
            const ev = new window.Event('scroll', { bubbles: true, cancelable: false });

            if (this.isDocumentScroller(scroller)) {
                window.dispatchEvent(ev);
                document.dispatchEvent(new window.Event('scroll', { bubbles: true, cancelable: false }));
            }
            else if (scroller) {
                scroller.dispatchEvent(ev);
            }
        },

        setScrollTop(scroller, value) {
            if (!scroller) return;

            if (this.isDocumentScroller(scroller)) {
                window.scrollTo(0, value);
            }
            else {
                scroller.scrollTop = value;
            }

            this.dispatchScrollEvent(scroller);
        },

        scrollByAmount(scroller, amount) {
            if (!scroller) return;

            if (this.isDocumentScroller(scroller)) {
                window.scrollBy(0, amount);
            }
            else {
                scroller.scrollTop = scroller.scrollTop + amount;
            }

            this.dispatchScrollEvent(scroller);
        },

        async scrollToTop() {
            const scroller = this.findScrollContainer();
            const before = this.getScrollTop(scroller);

            this.setScrollTop(scroller, 0);
            await this.sleep(800);

            return {
                ok: true,
                before,
                after: this.getScrollTop(scroller),
                scroller: this.elementDebug(scroller)
            };
        },

        async scrollDown() {
            const scroller = this.findScrollContainer();
            const before = this.getScrollTop(scroller);
            const amount = scroller && scroller.clientHeight
                ? Math.max(Math.floor(scroller.clientHeight * 0.75), 300)
                : 500;

            this.scrollByAmount(scroller, amount);
            await this.sleep(600);

            return {
                ok: true,
                before,
                after: this.getScrollTop(scroller),
                amount,
                changed: this.getScrollTop(scroller) !== before,
                scroller: this.elementDebug(scroller)
            };
        }
    };

    root.__ScanTargetSyncDomHelperParts = root.__ScanTargetSyncDomHelperParts || [];
    root.__ScanTargetSyncDomHelperParts.push(part);

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = part;
    }

    return true;
})(typeof window !== 'undefined' ? window : globalThis);

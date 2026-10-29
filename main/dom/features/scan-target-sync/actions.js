(function registerScanTargetSyncActionsPart(root) {
    const part = {
        summarizePreparedOperationContext(context) {
            if (!context) return null;

            return {
                name: context.name,
                kind: context.kind,
                isFixedLeft: context.isFixedLeft,
                endpointIndex: context.endpointIndex,
                columnCount: context.columnCount,
                selectionReason: context.selectionReason,
                rootConnected: !!(context.root && context.root.isConnected),
                preparedAt: context.preparedAt
            };
        },

        setPreparedOperationContext(selectedScope, selectionReason) {
            if (!selectedScope || !selectedScope.root || !selectedScope.operationHeader || !selectedScope.operationHeader.ok) {
                this._operationContext = null;
                return null;
            }

            this._operationContext = {
                name: selectedScope.name,
                kind: selectedScope.kind,
                isFixedLeft: selectedScope.isFixedLeft === true,
                root: selectedScope.root,
                operationHeader: selectedScope.operationHeader,
                endpointIndex: selectedScope.operationHeader.endpointIndex,
                columnCount: selectedScope.columnCount,
                selectionReason: selectionReason || '',
                preparedAt: new Date().toISOString()
            };

            return this._operationContext;
        },

        getPreparedOperationContext() {
            if (!this._operationContext) return null;
            if (!this._operationContext.root || !this._operationContext.root.isConnected) return null;
            return this._operationContext;
        },

        prepareOperationContext() {
            const rowScope = this.resolveDeviceRowScope();

            if (!rowScope.ok) {
                this._operationContext = null;
                return {
                    ok: false,
                    reason: rowScope.ambiguousReason || 'operation_scope_not_resolved',
                    selectionReason: rowScope.selectionReason,
                    ambiguousReason: rowScope.ambiguousReason,
                    validScopeCount: rowScope.validScopes.length,
                    scopeCandidateCount: rowScope.scopeCandidates.length,
                    scopes: rowScope.scopeCandidates.map(x => this.summarizeOperationScope(x))
                };
            }

            const context = this.setPreparedOperationContext(rowScope.selected, rowScope.selectionReason);

            return {
                ok: !!context,
                reason: context ? null : 'failed_to_prepare_operation_context',
                context: this.summarizePreparedOperationContext(context),
                selectedScope: this.summarizeOperationScope(rowScope.selected),
                selectionReason: rowScope.selectionReason,
                validScopeCount: rowScope.validScopes.length,
                scopeCandidateCount: rowScope.scopeCandidates.length
            };
        },

        async syncEndpointCheckbox(endpoint, desiredChecked) {
            const normalizedEndpoint = this.norm(endpoint);
            const desired = desiredChecked === true;
            const context = this.getPreparedOperationContext();

            if (!context) {
                return {
                    ok: false,
                    endpoint: normalizedEndpoint,
                    desiredChecked: desired,
                    reason: 'operation_context_not_prepared_or_disconnected'
                };
            }

            const candidates = this.findRowsByEndpoint(normalizedEndpoint);

            if (candidates.length === 0) {
                return {
                    ok: false,
                    endpoint: normalizedEndpoint,
                    desiredChecked: desired,
                    checked: null,
                    reason: 'endpoint_not_found_in_visible_rows',
                    context: this.summarizePreparedOperationContext(context)
                };
            }

            if (candidates.length > 1) {
                return {
                    ok: false,
                    endpoint: normalizedEndpoint,
                    desiredChecked: desired,
                    checked: null,
                    reason: 'duplicate_endpoint_in_visible_rows',
                    candidates: candidates.map(x => x.info),
                    context: this.summarizePreparedOperationContext(context)
                };
            }

            const row = candidates[0].row;
            const beforeInfo = candidates[0].info;
            const checkboxCandidates = this.getCheckboxCandidatesFromRow(row);

            if (checkboxCandidates.length !== 1) {
                return {
                    ok: false,
                    endpoint: normalizedEndpoint,
                    dataId: beforeInfo.dataId,
                    desiredChecked: desired,
                    checked: null,
                    reason: 'checkbox_candidate_count_not_one',
                    checkboxCandidateCount: checkboxCandidates.length,
                    row: beforeInfo,
                    context: this.summarizePreparedOperationContext(context)
                };
            }

            const checkbox = checkboxCandidates[0].input;
            const label = checkboxCandidates[0].label;

            if (this.isDisabled(checkbox) || this.isDisabled(label)) {
                return {
                    ok: false,
                    endpoint: normalizedEndpoint,
                    dataId: beforeInfo.dataId,
                    desiredChecked: desired,
                    checked: null,
                    reason: 'checkbox_disabled',
                    checkbox: this.elementDebug(checkbox),
                    label: this.elementDebug(label),
                    row: beforeInfo,
                    context: this.summarizePreparedOperationContext(context)
                };
            }

            const wasSelected = this.isRowSelected(row);
            const wasChecked = checkbox.checked === true;
            // この画面では input.checked だけでなく、行側の選択 class が実効選択状態を表すDOMがある。
            // そのため、設計上のチェック状態は row selected または checkbox.checked のORで評価する。
            const beforeEffectiveChecked = wasSelected || wasChecked;
            const alreadyAligned = beforeEffectiveChecked === desired;

            if (!alreadyAligned) {
                // このUIは label 側のクリックで行選択状態が更新されるため、クリック後にDOMを再取得して実効状態を検証する。
                label.click();
                await this.sleep(350);
            }

            const afterCandidates = this.findRowsByEndpoint(normalizedEndpoint);

            if (afterCandidates.length !== 1) {
                return {
                    ok: false,
                    endpoint: normalizedEndpoint,
                    dataId: beforeInfo.dataId,
                    desiredChecked: desired,
                    checked: null,
                    reason: 'endpoint_candidate_count_not_one_after_click',
                    afterCandidateCount: afterCandidates.length,
                    afterCandidates: afterCandidates.map(x => x.info),
                    wasSelected,
                    wasChecked,
                    beforeEffectiveChecked,
                    alreadyAligned,
                    changed: !alreadyAligned,
                    before: beforeInfo,
                    context: this.summarizePreparedOperationContext(context)
                };
            }

            const after = afterCandidates[0];
            const selectedNow = this.isRowSelected(after.row);
            const checkboxNow = this.getCheckboxCandidatesFromRow(after.row);

            if (checkboxNow.length !== 1) {
                return {
                    ok: false,
                    endpoint: normalizedEndpoint,
                    dataId: beforeInfo.dataId,
                    desiredChecked: desired,
                    checked: null,
                    reason: 'checkbox_candidate_count_not_one_after_click',
                    checkboxCandidateCount: checkboxNow.length,
                    wasSelected,
                    wasChecked,
                    beforeEffectiveChecked,
                    alreadyAligned,
                    changed: !alreadyAligned,
                    before: beforeInfo,
                    after: after.info,
                    context: this.summarizePreparedOperationContext(context)
                };
            }

            const checkedNow = checkboxNow[0].input.checked === true;
            const effectiveCheckedNow = selectedNow || checkedNow === true;

            if (effectiveCheckedNow !== desired) {
                return {
                    ok: false,
                    endpoint: normalizedEndpoint,
                    dataId: beforeInfo.dataId,
                    desiredChecked: desired,
                    checked: effectiveCheckedNow,
                    reason: 'selection_state_not_aligned_after_click',
                    wasSelected,
                    wasChecked,
                    beforeEffectiveChecked,
                    alreadyAligned,
                    changed: !alreadyAligned,
                    checkedNow,
                    selectedNow,
                    effectiveCheckedNow,
                    before: beforeInfo,
                    after: after.info,
                    context: this.summarizePreparedOperationContext(context)
                };
            }

            return {
                ok: true,
                endpoint: normalizedEndpoint,
                dataId: beforeInfo.dataId,
                desiredChecked: desired,
                checked: effectiveCheckedNow,
                changed: !alreadyAligned,
                alreadyAligned,
                wasSelected,
                wasChecked,
                beforeEffectiveChecked,
                checkedNow,
                selectedNow,
                effectiveCheckedNow,
                before: beforeInfo,
                after: after.info,
                context: this.summarizePreparedOperationContext(context)
            };
        },
    };

    root.__ScanTargetSyncDomHelperParts = root.__ScanTargetSyncDomHelperParts || [];
    root.__ScanTargetSyncDomHelperParts.push(part);

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = part;
    }

    return true;
})(typeof window !== 'undefined' ? window : globalThis);

(function registerInstalledAppExportAppsPart(root) {
    const part = {
        getTopLevelTabButtonCandidates(li) {
            if (!li) return [];

            return [...li.querySelectorAll('button')]
                .filter(button => button.closest('li') === li)
                .map(button => {
                    const span = button.querySelector('span[ng-bind="tab.label"]');
                    const text = span ? this.norm(span.textContent) : this.norm(button.textContent);

                    return {
                        li,
                        button,
                        span,
                        text,
                        topLevel: true,
                        active: this.isAppTabActive(li, button)
                    };
                });
        },

        isAppTabActive(li, button) {
            if (!li && !button) return false;

            return (!!li && li.classList.contains('active')) ||
                   (!!button && button.classList.contains('active')) ||
                   (!!button && button.getAttribute('aria-selected') === 'true');
        },

        resolveAppTab() {
            const panel = document.querySelector(this.selectors.frontPanel);
            const nav = panel ? panel.querySelector('nav ul.nav.navbar-nav') : null;
            const topLevelItems = nav
                ? [...nav.children].filter(el => el.tagName === 'LI')
                : [];
            const allTopLevelButtons = topLevelItems.flatMap(li => this.getTopLevelTabButtonCandidates(li));
            const visibleTabs = allTopLevelButtons
                .map((x, i) => ({
                    i,
                    text: x.text,
                    visible: !!x.button && this.isVisible(x.button),
                    disabled: this.isDisabled(x.button),
                    active: x.active,
                    className: x.button ? x.button.className : '',
                    liClassName: x.li ? x.li.className : '',
                    topLevel: true
                }))
                .filter(x => x.visible);
            const candidates = allTopLevelButtons
                .filter(x => x.button && this.isVisible(x.button))
                .filter(x => x.text === 'インストール済みアプリ');

            return {
                panel,
                nav,
                topLevelItemCount: topLevelItems.length,
                visibleTabs,
                candidates
            };
        },

        validateAppTabContract(requireActive) {
            const resolved = this.resolveAppTab();
            const checks = [];
            const target = resolved.candidates.length === 1 ? resolved.candidates[0] : null;
            const activeRequired = requireActive === true;

            checks.push(this.makeCheck(
                'detailPanel.root.visible',
                !!resolved.panel && this.isVisible(resolved.panel),
                'fatal',
                '詳細パネルが可視であること',
                { panel: this.elementDebug(resolved.panel) }
            ));

            checks.push(this.makeCheck(
                'tabs.nav.visible',
                !!resolved.nav && this.isVisible(resolved.nav),
                'fatal',
                '詳細パネル内のタブメニューが可視であること',
                { nav: this.elementDebug(resolved.nav) }
            ));

            checks.push(this.makeCheck(
                'tabs.app.exists',
                resolved.candidates.length > 0,
                'fatal',
                'トップレベル表示名「インストール済みアプリ」のタブ候補が存在すること',
                {
                    candidateCount: resolved.candidates.length,
                    visibleTabs: resolved.visibleTabs
                }
            ));

            checks.push(this.makeCheck(
                'tabs.app.unique',
                resolved.candidates.length === 1,
                'fatal',
                'トップレベル表示名「インストール済みアプリ」のタブ候補が一意であること',
                {
                    candidateCount: resolved.candidates.length,
                    visibleTabs: resolved.visibleTabs
                }
            ));

            checks.push(this.makeCheck(
                'tabs.app.enabled',
                !!target && !this.isDisabled(target.button),
                'fatal',
                'アプリタブのボタンが有効であること',
                { button: target ? this.elementDebug(target.button) : null }
            ));

            checks.push(this.makeCheck(
                'tabs.app.active',
                !!target && target.active === true,
                activeRequired ? 'fatal' : 'warning',
                activeRequired
                    ? 'アプリタブが active であること'
                    : 'クリック前は未activeを許容する。クリック後のアプリ一覧契約では fatal とする。',
                {
                    active: target ? target.active : false,
                    liClassName: target && target.li ? target.li.className : '',
                    button: target ? this.elementDebug(target.button) : null
                }
            ));

            return this.contractResult('appTab', checks, {
                visibleTabs: resolved.visibleTabs,
                requireActive: activeRequired
            });
        },

        resolveAppTabForClick() {
            const contract = this.validateAppTabContract(false);
            this.throwContractIfFatal(contract);

            const resolved = this.resolveAppTab();
            return resolved.candidates.length === 1 ? resolved.candidates[0] : null;
        },

        clickResolvedAppTab(target) {
            if (!target || !target.button) {
                throw new Error('clickResolvedAppTab: target is invalid');
            }

            const wasActive = target.active;

            if (!wasActive) {
                this.clickElement(target.button);
            }

            return {
                ok: true,
                action: wasActive ? 'app-tab-already-active' : 'click-app-tab',
                clickedText: target.text,
                wasActive,
                liClassBeforeClick: target.li ? target.li.className : ''
            };
        },

        clickAppTab() {
            const target = this.resolveAppTabForClick();
            return this.clickResolvedAppTab(target);
        },

        resolveAppContentScope() {
            const panel = document.querySelector(this.selectors.frontPanel);

            if (!panel || !this.isVisible(panel)) {
                return {
                    panel,
                    candidates: [],
                    meaningful: [],
                    target: null,
                    source: 'none'
                };
            }

            // .app-pane は主契約ではなく、補助的な探索スコープとして扱う。
            // 一意に解決できる場合は優先するが、解決できない場合でも frontPanel 内の業務意味要素
            // （radio / grid / 必須ヘッダー / CSV出力属性）で一意性を確認する。
            const candidates = [...panel.querySelectorAll('.app-pane')]
                .map((el, i) => ({
                    i,
                    el,
                    visible: this.isVisible(el),
                    hasRadio: !!el.querySelector(this.selectors.appRadio),
                    hasGrid: !!el.querySelector('#app-grid, #app-grid_headers'),
                    hasAppCsvArea: this.resolveAppCsvAreas(el).length > 0,
                    textPreview: this.norm(el.textContent).slice(0, 160)
                }))
                .filter(x => x.visible);

            const meaningful = candidates.filter(x => x.hasRadio || x.hasGrid || x.hasAppCsvArea);
            const auxiliaryTarget = meaningful.length === 1 ? meaningful[0].el : null;

            return {
                panel,
                candidates,
                meaningful,
                target: auxiliaryTarget || panel,
                source: auxiliaryTarget ? 'app-pane-class' : 'detail-panel'
            };
        },

        getAppTabRoot() {
            return this.resolveAppContentScope().target;
        },

        getAppTabCandidatesDebug() {
            const resolved = this.resolveAppContentScope();

            return resolved.candidates.map(x => ({
                i: x.i,
                visible: x.visible,
                textPreview: x.textPreview,
                hasRadio: x.hasRadio,
                hasGrid: x.hasGrid,
                appCsvAreaCount: this.resolveAppCsvAreas(x.el).length,
                meaningful: x.hasRadio || x.hasGrid || x.hasAppCsvArea
            }));
        },

        getAppHeaders(appTab) {
            if (!appTab) return [];

            const fromHeaderText = [...appTab.querySelectorAll(this.selectors.appGridHeaders)]
                .filter(el => this.isVisible(el) || this.isVisible(el.closest('th')))
                .map(el => this.norm(el.textContent));

            const fromAriaLabel = [...appTab.querySelectorAll('#app-grid_headers th[aria-label]')]
                .filter(el => this.isVisible(el))
                .map(el => this.norm(el.getAttribute('aria-label')));

            return [...new Set([...fromHeaderText, ...fromAriaLabel].filter(Boolean))];
        },

        resolveAppRadio(appTab) {
            if (!appTab) {
                return {
                    radio: null,
                    label: null,
                    candidates: [],
                    allRadios: []
                };
            }

            const allRadios = [...appTab.querySelectorAll(this.selectors.appRadio)]
                .map((radio, i) => {
                    const id = radio.id || '';
                    const label = id
                        ? appTab.querySelector('label[for="' + this.cssEscapeIdent(id) + '"]')
                        : null;
                    const visible = this.isVisible(radio) || this.isVisible(label);

                    return {
                        i,
                        radio,
                        label,
                        visible,
                        enabled: !this.isDisabled(radio),
                        checked: radio.checked === true
                    };
                });
            const visibleRadios = allRadios.filter(x => x.visible);
            const candidates = visibleRadios.length > 0 ? visibleRadios : allRadios;
            const target = candidates.length === 1 ? candidates[0] : null;

            return {
                radio: target ? target.radio : null,
                label: target ? target.label : null,
                candidates,
                allRadios
            };
        },

        resolveAppCsvAreas(appTab) {
            if (!appTab) return [];

            return [...appTab.querySelectorAll('div[data-download-url]')]
                .filter(el => {
                    return el.getAttribute('data-download-url') === "detail.csvUrl['app']" &&
                           el.getAttribute('data-before-download') === 'detail.beforeAppCsv(param)';
                })
                .filter(el => {
                    if (this.isVisible(el)) return true;
                    return [...el.querySelectorAll('button')].some(button => this.isVisible(button));
                });
        },

        resolveAppCsvButtons(csvArea) {
            if (!csvArea) {
                return {
                    candidates: [],
                    allButtons: []
                };
            }

            const allButtons = [...csvArea.querySelectorAll('button')]
                .map((btn, i) => ({
                    i,
                    element: btn,
                    text: this.norm(btn.textContent),
                    visible: this.isVisible(btn),
                    disabled: this.isDisabled(btn),
                    className: btn.className,
                    ngHide: btn.getAttribute('ng-hide'),
                    ngShow: btn.getAttribute('ng-show')
                }));

            const candidates = allButtons
                .filter(x => x.visible)
                .filter(x => !x.disabled)
                .filter(x => x.text === 'CSV出力');

            return { candidates, allButtons };
        },

        validateAppListContract() {
            const checks = [];
            const panel = document.querySelector(this.selectors.frontPanel);
            const tabContract = this.validateAppTabContract(true);
            const contentScopeResolution = this.resolveAppContentScope();
            const appScope = contentScopeResolution.target;
            const appGrids = appScope
                ? [...appScope.querySelectorAll('#app-grid, #app-grid_headers')]
                : [];
            const visibleAppGrids = appGrids.filter(el => this.isVisible(el));
            const appGrid = visibleAppGrids[0] || appGrids[0] || null;
            const headers = this.getAppHeaders(appScope);
            const missingHeaders = this.requiredAppHeaders.filter(h => !headers.includes(h));
            const radioResolution = this.resolveAppRadio(appScope);
            const { radio, label } = radioResolution;
            const csvAreas = this.resolveAppCsvAreas(appScope);
            const csvArea = csvAreas.length === 1 ? csvAreas[0] : null;
            const buttonResolution = this.resolveAppCsvButtons(csvArea);

            checks.push(...tabContract.checks);

            checks.push(this.makeCheck(
                'appContent.scope.resolved',
                !!appScope && this.isVisible(appScope),
                'fatal',
                'アプリ一覧の探索スコープを解決できること。通常は補助スコープ .app-pane、未解決時は #detail-panel を使う。',
                {
                    source: contentScopeResolution.source,
                    scope: this.elementDebug(appScope)
                }
            ));

            checks.push(this.makeCheck(
                'appContent.auxiliaryAppTab.unique',
                contentScopeResolution.meaningful.length <= 1,
                'warning',
                '.app-pane は補助スコープであり、存在しない場合は #detail-panel 内の業務意味要素で契約確認する。複数ある場合は診断情報として警告する。',
                {
                    candidateCount: contentScopeResolution.candidates.length,
                    meaningfulCount: contentScopeResolution.meaningful.length,
                    candidates: this.getAppTabCandidatesDebug(),
                    source: contentScopeResolution.source
                }
            ));

            checks.push(this.makeCheck(
                'appList.grid.exists',
                !!appGrid && (visibleAppGrids.length > 0 || headers.length > 0),
                'fatal',
                'アプリ一覧グリッド app-grid が存在し、現在表示中の一覧として確認できること',
                {
                    appGrid: this.elementDebug(appGrid),
                    gridCount: appGrids.length,
                    visibleGridCount: visibleAppGrids.length,
                    headerCount: headers.length
                }
            ));

            checks.push(this.makeCheck(
                'appList.headers.required',
                missingHeaders.length === 0,
                'fatal',
                'アプリ一覧に必須ヘッダー「アプリ名」「バージョン」「導入日」が存在すること。順序は問わない。',
                {
                    headers,
                    missingHeaders
                }
            ));

            checks.push(this.makeCheck(
                'app.radio.unique',
                radioResolution.candidates.length === 1,
                'fatal',
                'app-list-radio ラジオが現在の探索スコープ内で一意に解決できること',
                {
                    candidateCount: radioResolution.candidates.length,
                    allCount: radioResolution.allRadios.length,
                    candidates: radioResolution.allRadios.map(x => ({
                        i: x.i,
                        visible: x.visible,
                        enabled: x.enabled,
                        checked: x.checked,
                        radio: this.elementDebug(x.radio),
                        label: this.elementDebug(x.label)
                    }))
                }
            ));

            checks.push(this.makeCheck(
                'app.radio.exists',
                !!radio,
                'fatal',
                'app-list-radio ラジオが存在すること',
                { radio: this.elementDebug(radio), label: this.elementDebug(label) }
            ));

            checks.push(this.makeCheck(
                'app.radio.visible',
                !!radio && (this.isVisible(radio) || this.isVisible(label)),
                'fatal',
                'app-list-radio ラジオまたは対応ラベルが可視であること',
                { radio: this.elementDebug(radio), label: this.elementDebug(label) }
            ));

            checks.push(this.makeCheck(
                'app.radio.enabled',
                !!radio && !this.isDisabled(radio),
                'fatal',
                'app-list-radio ラジオが有効であること',
                { radio: this.elementDebug(radio) }
            ));

            checks.push(this.makeCheck(
                'app.radio.checked',
                !!radio && radio.checked === true,
                'fatal',
                'app-list-radio ラジオが選択済みであること。未選択の場合は想定外として停止する。',
                { checked: radio ? radio.checked : null }
            ));

            checks.push(this.makeCheck(
                'appCsvExport.area.unique',
                csvAreas.length === 1,
                'fatal',
                'app 用 CSV 出力領域が一意であること。実操作可能性は内部の CSV出力 ボタンで判定する。',
                {
                    candidateCount: csvAreas.length,
                    candidates: csvAreas.map(el => this.elementDebug(el))
                }
            ));

            checks.push(this.makeCheck(
                'appCsvExport.button.unique',
                buttonResolution.candidates.length === 1,
                'fatal',
                'app 用 CSV 出力領域内の可視・有効な「CSV出力」ボタンが一意であること',
                {
                    candidateCount: buttonResolution.candidates.length,
                    buttons: buttonResolution.allButtons.map(x => ({
                        i: x.i,
                        text: x.text,
                        visible: x.visible,
                        disabled: x.disabled,
                        className: x.className,
                        ngHide: x.ngHide,
                        ngShow: x.ngShow
                    }))
                }
            ));

            return this.contractResult('appList', checks, {
                contentScopeSource: contentScopeResolution.source,
                appTabCandidates: this.getAppTabCandidatesDebug(),
                headers,
                radioChecked: radio ? radio.checked : null
            });
        },

        assertAppRadioChecked() {
            const contract = this.validateAppListContract();
            this.throwContractIfFatal(contract);

            const appTab = this.getAppTabRoot();
            const { radio } = this.resolveAppRadio(appTab);

            return {
                ok: true,
                action: 'app-radio-checked-contract-satisfied',
                checked: radio ? radio.checked === true : false
            };
        },

        resolveAppCsvExportButton() {
            const contract = this.validateAppListContract();
            const appScope = this.getAppTabRoot();
            const csvAreas = this.resolveAppCsvAreas(appScope);
            const csvArea = csvAreas.length === 1 ? csvAreas[0] : null;
            const buttonResolution = this.resolveAppCsvButtons(csvArea);
            const button = buttonResolution.candidates.length === 1
                ? buttonResolution.candidates[0].element
                : null;

            return {
                ok: contract && contract.fatalCount === 0 && !!csvArea && !!button,
                contract,
                appScope,
                csvArea,
                button,
                areaCandidateCount: csvAreas.length,
                buttonCandidateCount: buttonResolution.candidates.length,
                buttons: buttonResolution.allButtons
            };
        },

        clickResolvedAppCsvButton(resolved) {
            if (!resolved || !resolved.ok || !resolved.csvArea || !resolved.button) {
                throw new Error('clickResolvedAppCsvButton: resolved csv button is invalid');
            }

            this.clickElement(resolved.button);

            return {
                ok: true,
                action: 'click-app-csv-output',
                clickedText: this.norm(resolved.button.textContent),
                downloadUrl: resolved.csvArea.getAttribute('data-download-url'),
                onBeforeDownload: resolved.csvArea.getAttribute('data-before-download')
            };
        },

        clickAppCsvButton() {
            const resolved = this.resolveAppCsvExportButton();
            this.throwContractIfFatal(resolved.contract);

            if (!resolved.ok) {
                throw new Error(
                    'app 用 CSV 出力ボタンが一意に解決できません。areaCandidateCount=' +
                    resolved.areaCandidateCount +
                    ' buttonCandidateCount=' +
                    resolved.buttonCandidateCount
                );
            }

            return this.clickResolvedAppCsvButton(resolved);
        },

    };

    root.__InstalledAppExportDomHelperParts = root.__InstalledAppExportDomHelperParts || [];
    root.__InstalledAppExportDomHelperParts.push(part);

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = part;
    }

    return true;
})(typeof window !== 'undefined' ? window : globalThis);

(function registerDeviceListExportExportPart(root) {
    const part = {
        buttonTextIsTask(text) {
            const normalized = this.norm(text);
            return normalized === '操作' || /^操作\s*$/.test(normalized);
        },

        collectTaskMenuElements(rootElement) {
            if (!rootElement) return [];

            const selector = '[role="menu"], .ui-dropdown-menu';
            const menus = [];

            if (rootElement.matches && rootElement.matches(selector)) {
                menus.push(rootElement);
            }

            for (const menu of [...rootElement.querySelectorAll(selector)]) {
                menus.push(menu);
            }

            return this.uniqueElements(menus);
        },

        resolveTaskMenuRoot(button) {
            if (!button) return null;

            // First prefer the known dropdown container classes used by this UI.
            // Do not use broad selectors such as [class*="dropdown"] because the
            // task button itself has dropdown-toggle classes and would become the root.
            const exactRoot = button.closest('.ui-dropdown, .ui-btn-group');
            if (exactRoot && exactRoot !== button && this.collectTaskMenuElements(exactRoot).length > 0) {
                return exactRoot;
            }

            // Fallback: walk ancestors until the document root and adopt the nearest
            // ancestor that contains both the task button and a menu. This is based on
            // the semantic relationship, not on an arbitrary depth limit.
            for (let current = button.parentElement; current && current !== document.documentElement; current = current.parentElement) {
                if (!current.contains(button)) continue;
                if (this.collectTaskMenuElements(current).length > 0) return current;
            }

            return null;
        },

        resolveTaskButton() {
            const candidates = [];
            for (const button of [...document.querySelectorAll('button')]) {
                const text = this.norm(button.textContent);
                const ariaHaspopup = this.norm(button.getAttribute('aria-haspopup'));
                const role = this.norm(button.getAttribute('role'));
                const hasPopup = ariaHaspopup === 'true' || ariaHaspopup === 'menu';
                const isRoleButton = role === '' || role === 'button';
                const isTask = this.buttonTextIsTask(text);

                if (!hasPopup || !isRoleButton || !isTask) continue;

                const root = this.resolveTaskMenuRoot(button);
                candidates.push({
                    element: button,
                    root,
                    debug: this.elementDebug(button),
                    rootDebug: this.elementDebug(root),
                    menuCount: this.collectTaskMenuElements(root).length
                });
            }

            const unique = this.uniqueElements(candidates.map(x => x.element)).map(el => {
                const candidate = candidates.filter(x => x.element === el)[0];
                return candidate;
            });
            const visible = unique.filter(x => this.isVisible(x.element));
            const element = visible.length === 1 ? visible[0].element : null;
            const root = visible.length === 1 ? visible[0].root : null;

            return {
                ok: visible.length === 1,
                element,
                root,
                count: visible.length,
                candidates: visible.map(x => ({ button: x.debug, root: x.rootDebug, menuCount: x.menuCount })).slice(0, 20),
                summary: element ? this.elementDebug(element) : null,
                rootSummary: root ? this.elementDebug(root) : null,
                menuCount: root ? this.collectTaskMenuElements(root).length : 0
            };
        },

        collectExportMenuItemCandidates(taskMenuRoot) {
            const menus = this.collectTaskMenuElements(taskMenuRoot);
            const items = [];

            for (const menu of menus) {
                // Prefer actual menuitem roles. Avoid wrapper elements such as
                // ui-menu-item-wrapper, which can have the same text and would
                // otherwise create duplicate candidates for the same business action.
                for (const item of [...menu.querySelectorAll('[role="menuitem"]')]) {
                    if (this.norm(item.textContent) !== 'CSV出力') continue;
                    items.push({
                        element: item,
                        menu: this.elementDebug(menu),
                        debug: this.elementDebug(item),
                        wrapper: this.elementDebug(item.closest('[role="presentation"], [class*="menu-item-wrapper"]')),
                        source: 'role-menuitem'
                    });
                }
            }

            if (items.length > 0) return items;

            for (const menu of menus) {
                for (const item of [...menu.querySelectorAll('[class*="menu-item"]')]) {
                    const className = String(item.className || '');
                    if (/menu-item-wrapper/.test(className)) continue;
                    if (this.norm(item.textContent) !== 'CSV出力') continue;
                    items.push({
                        element: item,
                        menu: this.elementDebug(menu),
                        debug: this.elementDebug(item),
                        wrapper: this.elementDebug(item.closest('[role="presentation"], [class*="menu-item-wrapper"]')),
                        source: 'class-menu-item'
                    });
                }
            }

            return items;
        },

        resolveExportMenuItem() {
            const taskButton = this.resolveTaskButton();
            if (!taskButton.ok || !taskButton.root) {
                return {
                    ok: false,
                    element: null,
                    count: 0,
                    reason: taskButton.ok ? 'task_menu_root_not_resolved' : 'task_button_not_resolved',
                    taskButton
                };
            }

            const items = this.collectExportMenuItemCandidates(taskButton.root);
            const unique = this.uniqueElements(items.map(x => x.element)).map(el => {
                const item = items.filter(x => x.element === el)[0];
                return item;
            });
            const visible = unique.filter(x => this.isVisible(x.element));
            const element = visible.length === 1 ? visible[0].element : null;

            return {
                ok: visible.length === 1,
                element,
                count: visible.length,
                totalCandidates: unique.length,
                taskButton: taskButton.summary,
                menuRoot: taskButton.rootSummary,
                menuCount: taskButton.menuCount,
                candidates: visible.map(x => ({ item: x.debug, wrapper: x.wrapper, menu: x.menu, source: x.source })).slice(0, 20),
                hiddenCandidates: unique.filter(x => !this.isVisible(x.element)).map(x => ({ item: x.debug, wrapper: x.wrapper, menu: x.menu, source: x.source })).slice(0, 20),
                summary: element ? this.elementDebug(element) : null
            };
        },

        async clickTaskButton() {
            const resolved = this.resolveTaskButton();
            if (!resolved.ok) {
                throw new Error('DOM契約違反: 操作ボタンが一意に特定できません。count=' + resolved.count);
            }

            const button = resolved.element;
            if (!this.isClickable(button)) {
                throw new Error('DOM契約違反: 操作ボタンがクリック可能ではありません。');
            }

            button.scrollIntoView({ block: 'center', inline: 'center' });
            await this.sleep(100);
            button.click();
            await this.sleep(300);

            return {
                ok: true,
                action: 'click-task-button',
                element: this.elementDebug(button),
                menuRoot: resolved.rootSummary,
                menuCount: resolved.menuCount,
                ariaExpanded: button.getAttribute('aria-expanded'),
                url: window.location.href || ''
            };
        },

        isTaskMenuReady() {
            const exportItem = this.resolveExportMenuItem();
            return exportItem.ok && this.isClickable(exportItem.element);
        },

        async clickExportMenuItem() {
            const resolved = this.resolveExportMenuItem();
            if (!resolved.ok) {
                throw new Error('DOM契約違反: 操作メニュー内のエクスポートが一意に特定できません。count=' + resolved.count + ' totalCandidates=' + (resolved.totalCandidates || 0) + ' reason=' + (resolved.reason || ''));
            }

            const item = resolved.element;
            if (!this.isClickable(item)) {
                throw new Error('DOM契約違反: 操作メニュー内のエクスポートがクリック可能ではありません。');
            }

            item.scrollIntoView({ block: 'center', inline: 'center' });
            await this.sleep(100);
            item.click();
            await this.sleep(300);

            const result = {
                ok: true,
                action: 'click-export',
                element: this.elementDebug(item),
                taskButton: resolved.taskButton,
                menuRoot: resolved.menuRoot,
                menuCount: resolved.menuCount,
                url: window.location.href || '',
                clickedAt: new Date().toISOString()
            };
            this._lastExportClickResult = result;
            return result;
        }
    };

    root.__DeviceListExportDomHelperParts = root.__DeviceListExportDomHelperParts || [];
    root.__DeviceListExportDomHelperParts.push(part);

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = part;
    }
})(typeof window !== 'undefined' ? window : globalThis);

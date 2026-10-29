(function () {
    'use strict';

    // ============================================================
    // ExampleSecurity mock: センサー / デバイス (既定グループ)
    //   - 一覧は仮想スクロールで描画する（表示範囲付近の行だけDOMに置く）。
    //   - 日付は「現在日時からの相対値」で生成するため、いつ開いても判定条件が成立する。
    // ============================================================

    const ROW_HEIGHT = 36;
    const BUFFER_ROWS = 4;
    const DEVICE_COUNT = 40;
    const EXPORT_FILE_NAME = 'sensor_devices.csv';
    const MINUTE = 60 * 1000;
    const DAY = 24 * 60 * MINUTE;

    const COLUMNS = [
        { key: 'host', label: 'ホスト名' },
        { key: 'user', label: '利用者' },
        { key: 'status', label: '接続状態' },
        { key: 'lastSeen', label: '最終通信日時' },
        { key: 'scanStarted', label: '手動スキャンの開始' },
        { key: 'scanCompleted', label: '手動スキャンの完了' },
        { key: 'os', label: 'OS' },
        { key: 'agentVersion', label: 'エージェントVer.' }
    ];

    const OS_NAMES = ['Windows 11 Pro', 'Windows 11 Pro', 'Windows 10 Pro', 'macOS 14'];

    const els = {
        scroll: document.getElementById('device-scroll'),
        table: document.getElementById('device-table'),
        count: document.getElementById('device-count'),
        search: document.getElementById('searchBox'),
        toast: document.getElementById('toast')
    };

    // ---- data ----

    // 再読み込みしても同じ端末構成になるよう、固定シードの擬似乱数を使う。
    function createRandom(seed) {
        let s = seed >>> 0;
        return function () {
            s = (s + 0x6d2b79f5) >>> 0;
            let t = s;
            t = Math.imul(t ^ (t >>> 15), t | 1);
            t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
        };
    }

    function pad(n) {
        return String(n).padStart(2, '0');
    }

    function formatDateTime(date) {
        if (!date) return '-';
        return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate()) + ' ' +
            pad(date.getHours()) + ':' + pad(date.getMinutes()) + ':' + pad(date.getSeconds());
    }

    function createDevices() {
        const random = createRandom(20260601);
        const now = Date.now();
        const devices = [];

        for (let i = 0; i < DEVICE_COUNT; i++) {
            const group = Math.floor(i / 10) + 1;
            const host = 'PCXX-' + pad(group) + '-' + String((i % 10) + 1).padStart(3, '0');
            const offline = random() < 0.2;
            const lastSeenAgo = offline
                ? (3 + Math.floor(random() * 20)) * DAY
                : Math.floor(random() * 8 * 60) * MINUTE;
            const lastSeen = new Date(now - lastSeenAgo);

            // 手動スキャン完了日と最終通信日時の差は、閾値(7日)の前後に分布させる。
            // 完了日が最終通信日時より新しくなることはない（CSVデータエラーになるため）。
            const roll = random();
            let scanCompleted = null;
            let scanStarted = null;

            if (roll < 0.15) {
                scanStarted = random() < 0.4 ? new Date(lastSeen.getTime() - 40 * MINUTE) : null;
            }
            else {
                const gapDays = roll < 0.6 ? Math.floor(random() * 6) : 7 + Math.floor(random() * 24);
                scanCompleted = new Date(lastSeen.getTime() - gapDays * DAY - (30 + Math.floor(random() * 240)) * MINUTE);
                scanStarted = new Date(scanCompleted.getTime() - (10 + Math.floor(random() * 80)) * MINUTE);
            }

            devices.push({
                id: 'd-' + String(i + 1).padStart(4, '0'),
                host,
                user: 'user' + String(i + 1).padStart(2, '0'),
                status: offline ? 'オフライン' : 'オンライン',
                lastSeen: formatDateTime(lastSeen),
                scanStarted: formatDateTime(scanStarted),
                scanCompleted: formatDateTime(scanCompleted),
                os: OS_NAMES[Math.floor(random() * OS_NAMES.length)],
                agentVersion: '14.0.' + (1200 + Math.floor(random() * 80)),
                // 一部は前回操作のチェックが残っている想定。ジョブはCSV判定に合わせてON/OFFを揃える。
                selected: i % 9 === 4
            });
        }

        return devices;
    }

    const state = {
        devices: createDevices(),
        view: [],
        first: -1,
        last: -1
    };

    // ---- rendering ----

    function createCheckbox(ariaLabel, checked) {
        const label = document.createElement('label');
        label.className = 'es-check';
        const input = document.createElement('input');
        input.type = 'checkbox';
        input.checked = checked;
        input.setAttribute('aria-label', ariaLabel);
        label.appendChild(input);
        return label;
    }

    function createHeaderRow() {
        const row = document.createElement('div');
        row.className = 'DataTable__row DataTable__row--header';
        row.setAttribute('role', 'row');

        const selectCell = document.createElement('div');
        selectCell.className = 'DataTable__header';
        selectCell.setAttribute('role', 'columnheader');
        selectCell.appendChild(createCheckbox('すべて選択', false));
        row.appendChild(selectCell);

        for (const column of COLUMNS) {
            const cell = document.createElement('div');
            cell.className = 'DataTable__header';
            cell.setAttribute('role', 'columnheader');
            cell.textContent = column.label;
            row.appendChild(cell);
        }

        return row;
    }

    function createDeviceRow(device) {
        const row = document.createElement('div');
        row.className = 'DataTable__row' + (device.selected ? ' tr-active' : '');
        row.setAttribute('role', 'row');
        row.setAttribute('data-id', device.id);
        row.setAttribute('aria-selected', String(device.selected));

        const selectCell = document.createElement('div');
        selectCell.className = 'DataTable__cell';
        selectCell.appendChild(createCheckbox(device.host + ' を選択', device.selected));
        row.appendChild(selectCell);

        for (const column of COLUMNS) {
            const cell = document.createElement('div');
            cell.className = 'DataTable__cell';
            cell.textContent = device[column.key];
            if (column.key === 'status') {
                cell.classList.add('es-status');
                if (device.status === 'オンライン') cell.classList.add('is-online');
            }
            row.appendChild(cell);
        }

        return row;
    }

    const headerRow = createHeaderRow();
    const topSpacer = document.createElement('div');
    const bottomSpacer = document.createElement('div');
    els.table.append(headerRow, topSpacer, bottomSpacer);

    function renderRows(force) {
        const total = state.view.length;
        const offset = Math.max(0, els.scroll.scrollTop - ROW_HEIGHT);
        const visibleCount = Math.ceil(els.scroll.clientHeight / ROW_HEIGHT);
        const first = Math.max(0, Math.floor(offset / ROW_HEIGHT) - BUFFER_ROWS);
        const last = Math.min(total, first + visibleCount + BUFFER_ROWS * 2);

        if (!force && first === state.first && last === state.last) return;
        state.first = first;
        state.last = last;

        for (const row of [...els.table.querySelectorAll('.DataTable__row[data-id]')]) {
            row.remove();
        }

        const fragment = document.createDocumentFragment();
        for (const device of state.view.slice(first, last)) {
            fragment.appendChild(createDeviceRow(device));
        }

        topSpacer.style.height = (first * ROW_HEIGHT) + 'px';
        bottomSpacer.style.height = ((total - last) * ROW_HEIGHT) + 'px';
        els.table.insertBefore(fragment, bottomSpacer);
        syncHeaderCheckbox();
    }

    function applyFilter() {
        const keyword = els.search.value.trim().toLowerCase();
        state.view = keyword
            ? state.devices.filter(d => d.host.toLowerCase().indexOf(keyword) >= 0)
            : state.devices.slice();
        els.scroll.scrollTop = 0;
        renderRows(true);
    }

    // ---- selection ----

    function findDevice(id) {
        return state.devices.find(d => d.id === id) || null;
    }

    function setRowSelected(row, selected) {
        row.classList.toggle('tr-active', selected);
        row.setAttribute('aria-selected', String(selected));
    }

    function syncHeaderCheckbox() {
        const input = headerRow.querySelector('input');
        const selectedCount = state.view.filter(d => d.selected).length;
        input.checked = state.view.length > 0 && selectedCount === state.view.length;
        input.indeterminate = selectedCount > 0 && selectedCount < state.view.length;
    }

    function syncScanMenu() {
        const anySelected = state.devices.some(d => d.selected);
        const scanItem = document.querySelector('[data-menu="scan"] [data-action="scan"]');
        if (anySelected) {
            scanItem.removeAttribute('aria-disabled');
        }
        else {
            scanItem.setAttribute('aria-disabled', 'true');
        }
    }

    els.table.addEventListener('change', event => {
        const input = event.target;
        if (!(input instanceof HTMLInputElement) || input.type !== 'checkbox') return;

        const row = input.closest('.DataTable__row');
        if (row === headerRow) {
            for (const device of state.view) device.selected = input.checked;
            for (const r of els.table.querySelectorAll('.DataTable__row[data-id]')) {
                setRowSelected(r, input.checked);
                r.querySelector('input').checked = input.checked;
            }
        }
        else {
            const device = findDevice(row.getAttribute('data-id'));
            device.selected = input.checked;
            setRowSelected(row, input.checked);
            syncHeaderCheckbox();
        }

        syncScanMenu();
    });

    // ---- dropdown menus ----

    function closeMenus(except) {
        for (const dropdown of document.querySelectorAll('[data-menu]')) {
            if (dropdown === except) continue;
            dropdown.querySelector('[role="menu"]').hidden = true;
            dropdown.querySelector('button').setAttribute('aria-expanded', 'false');
        }
    }

    for (const dropdown of document.querySelectorAll('[data-menu]')) {
        const button = dropdown.querySelector('button');
        const menu = dropdown.querySelector('[role="menu"]');

        button.addEventListener('click', event => {
            event.stopPropagation();
            closeMenus(dropdown);
            menu.hidden = !menu.hidden;
            button.setAttribute('aria-expanded', String(!menu.hidden));
        });

        menu.addEventListener('click', event => {
            event.stopPropagation();
            const item = event.target.closest('[role="menuitem"]');
            if (!item || item.getAttribute('aria-disabled') === 'true') return;

            closeMenus(null);
            runMenuAction(item.getAttribute('data-action'));
        });
    }

    document.addEventListener('click', () => closeMenus(null));

    function runMenuAction(action) {
        if (action === 'export') {
            exportDeviceCsv();
        }
        else if (action === 'scan') {
            const count = state.devices.filter(d => d.selected).length;
            showToast('（モック）' + count + '台の手動スキャン開始を受け付けました');
        }
        else {
            showToast('（モック）この操作は未実装です');
        }
    }

    // ---- CSV export ----

    function csvField(value) {
        return '"' + String(value).replace(/"/g, '""') + '"';
    }

    function exportDeviceCsv() {
        const lines = [COLUMNS.map(c => csvField(c.label)).join(',')];
        for (const device of state.devices) {
            lines.push(COLUMNS.map(c => csvField(device[c.key])).join(','));
        }

        // Windows PowerShell 5.1 の Import-Csv -Encoding UTF8 で読めるよう BOM 付き UTF-8 で出力する。
        const blob = new Blob(['﻿' + lines.join('\r\n') + '\r\n'], { type: 'text/csv;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = EXPORT_FILE_NAME;
        document.body.appendChild(link);
        link.click();
        link.remove();
        setTimeout(() => URL.revokeObjectURL(url), 10000);

        showToast('CSVを出力しました');
    }

    // ---- misc ----

    let toastTimer = null;

    function showToast(message) {
        els.toast.textContent = message;
        els.toast.hidden = false;
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => { els.toast.hidden = true; }, 2500);
    }

    // requestAnimationFrame はウィンドウ最小化中に止まるため、scroll イベント内で直接描画する。
    els.scroll.addEventListener('scroll', () => renderRows(false));
    window.addEventListener('resize', () => renderRows(true));
    els.search.addEventListener('input', applyFilter);

    els.count.textContent = 'センサー: ' + state.devices.length;
    applyFilter();
    syncScanMenu();
})();

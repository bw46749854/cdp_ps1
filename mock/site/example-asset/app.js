(function () {
    'use strict';

    // ============================================================
    // ExampleAsset mock: 端末一覧
    //   - 一覧は固定列側（選択・端末名）と通常列側（その他の列）に分かれ、同じ data-id の行を両側に描画する。
    //   - 端末名セルのクリックで右側の詳細パネルを開く（読み込み待ちを再現するため少し遅延させる）。
    //   - 導入日は現在日付からの相対値で生成し、常に「前月の導入」を含むようにする。
    // ============================================================

    const DEVICE_COUNT = 12;
    const DETAIL_LOAD_DELAY_MS = 250;
    const DAY = 24 * 60 * 60 * 1000;

    const APP_CATALOG = [
        { name: 'Office Suite', publisher: 'Example Soft' },
        { name: 'PDF Reader', publisher: 'Example Soft' },
        { name: 'Web Browser', publisher: 'Sample Labs' },
        { name: 'Zip Archiver', publisher: 'Open Tools' },
        { name: 'Chat Client', publisher: 'Sample Labs' },
        { name: 'VPN Client', publisher: 'NetSample' },
        { name: 'Remote Support Tool', publisher: 'NetSample' },
        { name: 'Text Editor', publisher: 'Open Tools' },
        { name: 'Image Viewer', publisher: 'Open Tools' },
        { name: 'Runtime Library 2022', publisher: 'Example Soft' },
        { name: 'Backup Agent', publisher: 'Sample Labs' },
        { name: 'Diagram Editor', publisher: 'Example Soft' }
    ];

    const OS_NAMES = ['Windows 11 Pro', 'Windows 11 Pro', 'Windows 10 Pro'];

    const els = {
        fixedBody: document.querySelector('#asset-grid_fixed tbody'),
        mainBody: document.querySelector('#asset-grid tbody'),
        fixedScroll: document.getElementById('asset-grid_fixedBodyContainer'),
        mainScroll: document.getElementById('asset-grid_scroll'),
        count: document.querySelector('[ng-bind="assetList.totalCount"]'),
        selectAll: document.querySelector('#asset-grid_all_select input'),
        panel: document.getElementById('detail-panel'),
        panelName: document.querySelector('#detail-panel [ng-bind="detail.item.name"]'),
        tabItems: [...document.querySelectorAll('#detail-panel .navbar-nav > li')],
        tabBodies: [...document.querySelectorAll('#detail-panel [data-tab-body]')],
        summary: document.getElementById('summary-props'),
        network: document.getElementById('network-props'),
        appBody: document.querySelector('#app-grid tbody'),
        appRadio: document.getElementById('app-list-radio'),
        updateRadio: document.getElementById('update-list-radio'),
        csvButton: document.querySelector('.ea-csv button'),
        toast: document.getElementById('toast')
    };

    // ---- data ----

    // 再読み込みしても同じ構成になるよう、固定シードの擬似乱数を使う。
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

    function formatDate(date) {
        return date.getFullYear() + '/' + pad(date.getMonth() + 1) + '/' + pad(date.getDate());
    }

    function formatDateTime(date) {
        return formatDate(date) + ' ' + pad(date.getHours()) + ':' + pad(date.getMinutes());
    }

    function pick(random, items, count) {
        const pool = items.slice();
        const picked = [];
        while (picked.length < count && pool.length > 0) {
            picked.push(pool.splice(Math.floor(random() * pool.length), 1)[0]);
        }
        return picked;
    }

    function createApps(random, index) {
        const now = new Date();
        const prevMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        const daysInPrevMonth = new Date(now.getFullYear(), now.getMonth(), 0).getDate();
        const apps = pick(random, APP_CATALOG, 6 + Math.floor(random() * 4));

        // 前月導入は端末ごとに0〜3件。0件の端末も混ぜて、抽出結果に差が出るようにする。
        const prevMonthCount = index % 4 === 3 ? 0 : 1 + Math.floor(random() * 3);

        return apps.map((app, i) => {
            let installed;
            if (i < prevMonthCount) {
                installed = new Date(prevMonthStart.getTime() + Math.floor(random() * daysInPrevMonth) * DAY);
            }
            else if (i === prevMonthCount && random() < 0.5 && now.getDate() > 1) {
                // 当月導入（前月抽出の対象外）。
                installed = new Date(now.getFullYear(), now.getMonth(), 1 + Math.floor(random() * (now.getDate() - 1)));
            }
            else {
                installed = new Date(prevMonthStart.getTime() - (20 + Math.floor(random() * 700)) * DAY);
            }

            return {
                name: app.name,
                version: (1 + Math.floor(random() * 9)) + '.' + Math.floor(random() * 10) + '.' + Math.floor(random() * 300),
                publisher: app.publisher,
                installDate: formatDate(installed)
            };
        }).concat(index === 5 ? [{
            // 導入日が取得できないアプリ。LastMonthInstallExtract ジョブの失敗一覧に載る例として1件だけ置く。
            name: 'Legacy Tool',
            version: '0.9.1',
            publisher: 'Unknown',
            installDate: ''
        }] : []);
    }

    function createUpdates(random) {
        const now = new Date();
        return [1, 2, 3].map(monthsAgo => {
            const date = new Date(now.getFullYear(), now.getMonth() - monthsAgo, 10 + Math.floor(random() * 10));
            return {
                name: '累積更新プログラム (' + date.getFullYear() + '-' + pad(date.getMonth() + 1) + ')',
                version: '-',
                publisher: 'OS Vendor',
                installDate: formatDate(date)
            };
        });
    }

    function createAssets() {
        const random = createRandom(20260701);
        const now = Date.now();
        const assets = [];

        for (let i = 0; i < DEVICE_COUNT; i++) {
            const group = Math.floor(i / 10) + 1;
            assets.push({
                id: String(101 + i),
                name: 'PCXX-' + pad(group) + '-' + String((i % 10) + 1).padStart(3, '0'),
                os: OS_NAMES[Math.floor(random() * OS_NAMES.length)],
                user: 'user' + String(i + 1).padStart(2, '0'),
                ip: '192.0.2.' + (10 + i),
                mac: '00-00-5E-00-53-' + pad((i + 16).toString(16).toUpperCase()),
                lastSeen: formatDateTime(new Date(now - Math.floor(random() * 3 * DAY))),
                apps: createApps(random, i),
                updates: createUpdates(random)
            });
        }

        return assets;
    }

    const state = {
        assets: createAssets(),
        current: null,
        loadTimer: null
    };

    // ---- asset grid ----

    function createRow(asset) {
        const tr = document.createElement('tr');
        tr.setAttribute('data-id', asset.id);
        tr.setAttribute('role', 'row');
        tr.setAttribute('aria-selected', 'false');
        return tr;
    }

    function createCell(text, columnId, className) {
        const td = document.createElement('td');
        td.textContent = text;
        td.setAttribute('aria-describedby', columnId);
        if (className) td.className = className;
        return td;
    }

    function renderGrid() {
        const fixedRows = document.createDocumentFragment();
        const mainRows = document.createDocumentFragment();

        for (const asset of state.assets) {
            const fixedRow = createRow(asset);
            const select = document.createElement('td');
            const checkbox = document.createElement('input');
            checkbox.type = 'checkbox';
            checkbox.setAttribute('aria-label', asset.name + ' を選択');
            select.appendChild(checkbox);
            fixedRow.appendChild(select);
            fixedRow.appendChild(createCell(asset.name, 'asset-grid_asset_name', 'ea-name-cell'));
            fixedRows.appendChild(fixedRow);

            const mainRow = createRow(asset);
            mainRow.appendChild(createCell(asset.os, 'asset-grid_os'));
            mainRow.appendChild(createCell(asset.user, 'asset-grid_user'));
            mainRow.appendChild(createCell(asset.ip, 'asset-grid_ip'));
            mainRow.appendChild(createCell(asset.lastSeen, 'asset-grid_last_seen'));
            mainRows.appendChild(mainRow);
        }

        els.fixedBody.appendChild(fixedRows);
        els.mainBody.appendChild(mainRows);
        els.count.textContent = String(state.assets.length);
    }

    function rowsFor(dataId) {
        return document.querySelectorAll('#asset-grid_container tr[data-id="' + dataId + '"]');
    }

    function selectRow(dataId) {
        for (const tr of document.querySelectorAll('#asset-grid_container tbody tr[data-id]')) {
            const selected = tr.getAttribute('data-id') === dataId;
            tr.setAttribute('aria-selected', String(selected));
            tr.classList.toggle('selected-row', selected);
        }
    }

    // 固定列側と通常列側の縦スクロール位置を揃える（値が同じなら scroll イベントは発生しない）。
    els.mainScroll.addEventListener('scroll', () => { els.fixedScroll.scrollTop = els.mainScroll.scrollTop; });
    els.fixedScroll.addEventListener('scroll', () => { els.mainScroll.scrollTop = els.fixedScroll.scrollTop; });

    // 行のホバー表示も両側で揃える。
    for (const body of [els.fixedBody, els.mainBody]) {
        body.addEventListener('mouseover', event => {
            const tr = event.target.closest('tr[data-id]');
            for (const row of document.querySelectorAll('#asset-grid_container tr.is-hover')) row.classList.remove('is-hover');
            if (tr) for (const row of rowsFor(tr.getAttribute('data-id'))) row.classList.add('is-hover');
        });
        body.addEventListener('mouseleave', () => {
            for (const row of document.querySelectorAll('#asset-grid_container tr.is-hover')) row.classList.remove('is-hover');
        });
    }

    els.fixedBody.addEventListener('click', event => {
        const cell = event.target.closest('td[aria-describedby="asset-grid_asset_name"]');
        if (!cell) return;

        const dataId = cell.closest('tr').getAttribute('data-id');
        selectRow(dataId);
        openDetail(state.assets.find(a => a.id === dataId));
    });

    els.selectAll.addEventListener('change', () => {
        for (const checkbox of els.fixedBody.querySelectorAll('input[type="checkbox"]')) {
            checkbox.checked = els.selectAll.checked;
        }
    });

    // ---- detail panel ----

    function fillProps(dl, pairs) {
        dl.textContent = '';
        for (const [label, value] of pairs) {
            const dt = document.createElement('dt');
            dt.textContent = label;
            const dd = document.createElement('dd');
            dd.textContent = value;
            dl.append(dt, dd);
        }
    }

    function activateTab(name) {
        for (const li of els.tabItems) {
            const active = li.getAttribute('data-tab') === name;
            li.classList.toggle('active', active);
            li.querySelector('button').setAttribute('aria-selected', String(active));
        }
        for (const body of els.tabBodies) {
            body.hidden = body.getAttribute('data-tab-body') !== name;
        }
    }

    function renderAppGrid() {
        const asset = state.current;
        const rows = !asset ? [] : (els.appRadio.checked ? asset.apps : asset.updates);
        els.appBody.textContent = '';

        for (const item of rows) {
            const tr = document.createElement('tr');
            for (const value of [item.name, item.version, item.publisher, item.installDate]) {
                const td = document.createElement('td');
                td.textContent = value;
                tr.appendChild(td);
            }
            els.appBody.appendChild(tr);
        }
    }

    function openDetail(asset) {
        clearTimeout(state.loadTimer);
        state.current = null;
        els.panelName.textContent = '';
        els.panel.hidden = false;

        // 実画面と同様に、名前と内容は少し遅れて表示される。
        state.loadTimer = setTimeout(() => {
            state.current = asset;
            els.panelName.textContent = asset.name;
            fillProps(els.summary, [
                ['端末名', asset.name],
                ['OS', asset.os],
                ['利用者', asset.user],
                ['最終通信日時', asset.lastSeen]
            ]);
            fillProps(els.network, [
                ['IPアドレス', asset.ip],
                ['MACアドレス', asset.mac]
            ]);
            els.appRadio.checked = true;
            renderAppGrid();
            activateTab('summary');
        }, DETAIL_LOAD_DELAY_MS);
    }

    function closeDetail() {
        clearTimeout(state.loadTimer);
        els.panel.hidden = true;
    }

    document.querySelector('#detail-panel .close-btn').addEventListener('click', closeDetail);

    for (const li of els.tabItems) {
        li.querySelector('button').addEventListener('click', () => activateTab(li.getAttribute('data-tab')));
    }

    els.appRadio.addEventListener('change', renderAppGrid);
    els.updateRadio.addEventListener('change', renderAppGrid);

    // ---- CSV export ----

    function csvField(value) {
        return '"' + String(value).replace(/"/g, '""') + '"';
    }

    function todayStamp() {
        const now = new Date();
        return now.getFullYear() + pad(now.getMonth() + 1) + pad(now.getDate());
    }

    els.csvButton.addEventListener('click', () => {
        const asset = state.current;
        if (!asset) return;

        const isAppList = els.appRadio.checked;
        const rows = isAppList ? asset.apps : asset.updates;
        const lines = ['アプリ名,バージョン,導入日'.split(',').map(csvField).join(',')];
        for (const item of rows) {
            lines.push([item.name, item.version, item.installDate].map(csvField).join(','));
        }

        // 実画面と同じく、ファイル名は端末名を含まない。端末名の付与はジョブ側のリネームで行う。
        const fileName = (isAppList ? 'app_list_' : 'update_list_') + todayStamp() + '.csv';
        const blob = new Blob(['﻿' + lines.join('\r\n') + '\r\n'], { type: 'text/csv;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = fileName;
        document.body.appendChild(link);
        link.click();
        link.remove();
        setTimeout(() => URL.revokeObjectURL(url), 10000);

        showToast('CSVを出力しました: ' + fileName);
    });

    // ---- misc ----

    let toastTimer = null;

    function showToast(message) {
        els.toast.textContent = message;
        els.toast.hidden = false;
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => { els.toast.hidden = true; }, 2500);
    }

    renderGrid();
})();

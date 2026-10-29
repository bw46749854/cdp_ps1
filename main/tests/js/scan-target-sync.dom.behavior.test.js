const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..', '..');
const scanTargetSyncScripts = [
  'dom/features/scan-target-sync/contract.js',
  'dom/features/scan-target-sync/list.js',
  'dom/features/scan-target-sync/actions.js',
  'dom/features/scan-target-sync/index.js',
];

class FakeElement {
  constructor(options = {}) {
    this.tagName = options.tagName || 'DIV';
    this.id = options.id || '';
    this.className = options.className || '';
    this.textContent = options.textContent || '';
    this.attributes = Object.assign({}, options.attributes || {});
    this.children = options.children || [];
    this.checked = options.checked === true;
    this.disabled = options.disabled === true;
    this.visible = options.visible !== false;
    this.isConnected = options.isConnected !== false;
    this.parentElement = options.parentElement || null;
    this.onClick = options.onClick || null;

    for (const child of this.children) {
      child.parentElement = this;
    }
  }

  get classList() {
    return this.className.split(/\s+/).filter(Boolean);
  }

  getBoundingClientRect() {
    return this.visible ? { width: 10, height: 10 } : { width: 0, height: 0 };
  }

  getAttribute(name) {
    if (name === 'id') return this.id || null;
    if (name === 'class') return this.className || null;
    if (Object.prototype.hasOwnProperty.call(this.attributes, name)) {
      return this.attributes[name];
    }
    return null;
  }

  hasAttribute(name) {
    return Object.prototype.hasOwnProperty.call(this.attributes, name);
  }

  closest(selector) {
    if (selector === '[disabled]' && this.disabled) return this;
    if (selector === '[aria-disabled="true"]' && this.getAttribute('aria-disabled') === 'true') return this;
    if (selector === '[class*="disabled"]' && this.className.indexOf('disabled') >= 0) return this;
    return null;
  }

  querySelector(selector) {
    return this.querySelectorAll(selector)[0] || null;
  }

  querySelectorAll(selector) {
    const descendants = [];
    const visit = element => {
      for (const child of element.children || []) {
        descendants.push(child);
        visit(child);
      }
    };
    visit(this);

    if (selector === 'label') {
      return descendants.filter(x => x.tagName === 'LABEL');
    }

    if (selector === 'input[type="checkbox"]') {
      return descendants.filter(x => x.tagName === 'INPUT' && x.attributes.type === 'checkbox');
    }

    if (selector.indexOf('DataTable__row') >= 0) {
      return descendants.filter(x => x.className.indexOf('DataTable__row') >= 0);
    }

    return [];
  }

  click() {
    if (this.onClick) {
      this.onClick();
    }
  }
}

function createRow(endpoint, dataId, checked) {
  const checkbox = new FakeElement({
    tagName: 'INPUT',
    attributes: { type: 'checkbox' },
    checked,
  });
  const label = new FakeElement({
    tagName: 'LABEL',
    children: [checkbox],
    onClick: () => {
      checkbox.checked = !checkbox.checked;
    },
  });
  const checkboxCell = new FakeElement({
    className: 'DataTable__cell',
    children: [label],
  });
  const endpointCell = new FakeElement({
    className: 'DataTable__cell',
    textContent: endpoint,
  });
  const row = new FakeElement({
    className: 'DataTable__row',
    attributes: { 'data-id': dataId, 'aria-selected': 'false' },
    children: [checkboxCell, endpointCell],
    textContent: endpoint,
  });

  return { row, checkbox, label };
}

function createDocument(row) {
  const viewport = new FakeElement({ id: 'viewport', textContent: 'ExampleSecurity Cloud Service デバイス (既定グループ) センサー' });
  const searchBox = new FakeElement({ tagName: 'INPUT', id: 'searchBox', attributes: { name: 'searchBox' } });
  const count = new FakeElement({ tagName: 'SPAN', textContent: 'センサー: 1' });
  const sensorNavigation = new FakeElement({
    tagName: 'A',
    textContent: 'センサー',
    attributes: { 'data-components': 'sidenav-item-devices' },
  });

  return {
    readyState: 'complete',
    title: 'ExampleSecurity Cloud Service デバイス (既定グループ) センサー',
    documentElement: new FakeElement({ tagName: 'HTML' }),
    body: new FakeElement({ tagName: 'BODY' }),
    scrollingElement: new FakeElement({ tagName: 'HTML' }),
    querySelector(selector) {
      return this.querySelectorAll(selector)[0] || null;
    },
    querySelectorAll(selector) {
      if (selector === '#viewport') return [viewport];
      if (selector === '[data-components="sidenav-item-devices"]') return [sensorNavigation];
      if (selector === 'input#searchBox[name="searchBox"]') return [searchBox];
      if (selector === 'span, div') return [count, viewport];
      if (selector.indexOf('DataTable__row') >= 0) return [row];
      if (selector === '[role="menuitem"]') return [];
      return [];
    },
    dispatchEvent() {},
  };
}

function loadDomHelper(document) {
  const context = {
    window: {
      getComputedStyle() {
        return { display: 'block', visibility: 'visible', opacity: '1' };
      },
      setTimeout(callback) {
        callback();
        return 0;
      },
      scrollY: 0,
      scrollTo() {},
      scrollBy() {},
      dispatchEvent() {},
      Event: class {
        constructor(type, options) {
          this.type = type;
          this.options = options || {};
        }
      },
    },
    document,
    console,
  };

  vm.createContext(context);
  for (const relativePath of scanTargetSyncScripts) {
    const source = fs.readFileSync(path.join(root, relativePath), 'utf8');
    vm.runInContext(source, context, { filename: relativePath });
  }

  return context.window.__ScanTargetSyncDomHelper;
}

(async () => {
  const rowFixture = createRow('EP-001', 'row-1', false);
  const document = createDocument(rowFixture.row);
  const domHelper = loadDomHelper(document);

  assert.ok(domHelper, 'helper should be registered on window.__ScanTargetSyncDomHelper');
  for (const methodName of [
    'validateDevicePageContract',
    'validateDeviceListContract',
    'prepareOperationContext',
    'findDeviceRowsInfo',
    'syncEndpointCheckbox',
    'validatePostSelectionContract',
  ]) {
    assert.strictEqual(typeof domHelper[methodName], 'function', `${methodName} should be a function`);
  }

  const pageContract = domHelper.validateDevicePageContract();
  assert.strictEqual(pageContract.scope, 'scanTargetSyncDevicePage');
  assert.strictEqual(pageContract.ok, true);
  assert.strictEqual(pageContract.fatalCount, 0);
  assert.strictEqual(pageContract.details.totalCount, 1);

  const rootElement = new FakeElement({ children: [rowFixture.row] });
  domHelper._operationContext = {
    name: 'fixedLeftTable#0',
    kind: 'fixedLeftTable',
    isFixedLeft: true,
    root: rootElement,
    operationHeader: { ok: true, endpointIndex: 1 },
    endpointIndex: 1,
    columnCount: 2,
    selectionReason: 'test',
    preparedAt: '2026-06-15T00:00:00.000Z',
  };

  const rows = domHelper.findDeviceRowsInfo();
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].endpoint, 'EP-001');
  assert.strictEqual(rows[0].dataId, 'row-1');
  assert.strictEqual(rows[0].effectiveChecked, false);

  const alignedResult = await domHelper.syncEndpointCheckbox('EP-001', false);
  assert.strictEqual(alignedResult.ok, true);
  assert.strictEqual(alignedResult.alreadyAligned, true);
  assert.strictEqual(alignedResult.changed, false);
  assert.strictEqual(rowFixture.checkbox.checked, false);

  const changedResult = await domHelper.syncEndpointCheckbox('EP-001', true);
  assert.strictEqual(changedResult.ok, true);
  assert.strictEqual(changedResult.alreadyAligned, false);
  assert.strictEqual(changedResult.changed, true);
  assert.strictEqual(changedResult.checked, true);
  assert.strictEqual(rowFixture.checkbox.checked, true);

  console.log('ScanTargetSync DOM behavior tests passed.');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});

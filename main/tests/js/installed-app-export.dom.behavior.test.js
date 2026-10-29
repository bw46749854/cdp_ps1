const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..', '..');
const installedAppExportScripts = [
  'dom/features/installed-app-export/contract.js',
  'dom/features/installed-app-export/list.js',
  'dom/features/installed-app-export/detail.js',
  'dom/features/installed-app-export/apps.js',
  'dom/features/installed-app-export/actions.js',
  'dom/features/installed-app-export/index.js',
];

class FakeElement {
  constructor(options = {}) {
    this.tagName = (options.tagName || 'DIV').toUpperCase();
    this.id = options.id || '';
    this.className = options.className || '';
    this._textContent = options.textContent || '';
    this.attributes = Object.assign({}, options.attributes || {});
    this.children = options.children || [];
    this.parentElement = options.parentElement || null;
    this.visible = options.visible !== false;
    this.disabled = options.disabled === true;
    this.checked = options.checked === true;
    this.scrollHeight = options.scrollHeight || 100;
    this.clientHeight = options.clientHeight || 20;
    this.scrollTop = options.scrollTop || 0;
    this.offsetTop = options.offsetTop || 0;
    this.offsetHeight = options.offsetHeight || 20;
    this.onClick = options.onClick || null;
    this.dispatchedEvents = [];

    for (const child of this.children) {
      child.parentElement = this;
    }
  }

  get textContent() {
    const childText = this.children.map(child => child.textContent).join('');
    return this._textContent + childText;
  }

  set textContent(value) {
    this._textContent = value || '';
  }

  get classList() {
    const classes = this.className.split(/\s+/).filter(Boolean);
    classes.contains = name => classes.indexOf(name) >= 0;
    return classes;
  }

  getBoundingClientRect() {
    return this.visible ? { left: 0, top: 0, width: 10, height: 10 } : { left: 0, top: 0, width: 0, height: 0 };
  }

  getAttribute(name) {
    if (name === 'id') return this.id || null;
    if (name === 'class') return this.className || null;
    if (Object.prototype.hasOwnProperty.call(this.attributes, name)) return this.attributes[name];
    return null;
  }

  setAttribute(name, value) {
    if (name === 'id') this.id = String(value);
    else if (name === 'class') this.className = String(value);
    else this.attributes[name] = String(value);
  }

  hasAttribute(name) {
    if (name === 'id') return !!this.id;
    if (name === 'class') return !!this.className;
    return Object.prototype.hasOwnProperty.call(this.attributes, name);
  }

  contains(element) {
    if (element === this) return true;
    return this.children.some(child => child.contains(element));
  }

  matches(selector) {
    return selector.split(',').some(part => matchesSimpleSelector(this, part.trim()));
  }

  closest(selector) {
    for (let current = this; current; current = current.parentElement) {
      if (current.matches(selector)) return current;
    }
    return null;
  }

  getDescendants() {
    const result = [];
    const visit = element => {
      for (const child of element.children) {
        result.push(child);
        visit(child);
      }
    };
    visit(this);
    return result;
  }

  querySelector(selector) {
    return this.querySelectorAll(selector)[0] || null;
  }

  querySelectorAll(selector) {
    const selectors = selector.split(',').map(x => x.trim()).filter(Boolean);
    const result = [];
    for (const descendant of this.getDescendants()) {
      if (selectors.some(part => matchesSelectorChain(descendant, part, this))) {
        result.push(descendant);
      }
    }
    return [...new Set(result)];
  }

  scrollIntoView() {}

  dispatchEvent(event) {
    this.dispatchedEvents.push(event.type || String(event));
    if ((event.type || '') === 'click' && this.onClick) this.onClick();
    return true;
  }

  click() {
    if (this.onClick) this.onClick();
  }
}

function parseSimpleSelector(selector) {
  const selectorWithoutAttributes = selector.replace(/\[[^\]]+\]/g, '');
  const tagMatch = selectorWithoutAttributes.match(/^[a-zA-Z][a-zA-Z0-9_-]*/);
  const tagName = tagMatch ? tagMatch[0].toUpperCase() : '';
  const idMatches = [...selectorWithoutAttributes.matchAll(/#([a-zA-Z0-9_-]+)/g)].map(x => x[1]);
  const classMatches = [...selectorWithoutAttributes.matchAll(/\.([^.#\[]+)/g)].map(x => x[1]);
  const attrMatches = [...selector.matchAll(/\[([^\]=~*]+)(\*?=)?(?:"([^"]*)"|'([^']*)'|([^\]]*))?\]/g)].map(x => ({
    name: x[1].trim(),
    op: x[2] || '',
    value: (x[3] || x[4] || x[5] || '').trim(),
  }));
  return { tagName, idMatches, classMatches, attrMatches };
}

function matchesSimpleSelector(element, selector) {
  if (!selector || selector === '*') return true;
  const parsed = parseSimpleSelector(selector);
  if (parsed.tagName && element.tagName !== parsed.tagName) return false;
  for (const id of parsed.idMatches) {
    if (element.id !== id) return false;
  }
  const classes = element.className.split(/\s+/).filter(Boolean);
  for (const className of parsed.classMatches) {
    if (classes.indexOf(className) < 0) return false;
  }
  for (const attr of parsed.attrMatches) {
    const value = element.getAttribute(attr.name);
    if (!attr.op && value === null) return false;
    if (attr.op === '=' && value !== attr.value) return false;
    if (attr.op === '*=' && String(value || '').indexOf(attr.value) < 0) return false;
  }
  return true;
}

function matchesSelectorChain(element, selector, rootElement) {
  const tokens = selector.split(/\s+/).filter(Boolean);
  if (tokens.length === 0 || !matchesSimpleSelector(element, tokens[tokens.length - 1])) return false;
  let current = element.parentElement;
  for (let i = tokens.length - 2; i >= 0; i -= 1) {
    while (current && current !== rootElement.parentElement && !matchesSimpleSelector(current, tokens[i])) {
      current = current.parentElement;
    }
    if (!current || current === rootElement.parentElement) return false;
    current = current.parentElement;
  }
  return true;
}

class FakeDocument extends FakeElement {
  constructor(children) {
    super({ tagName: 'DOCUMENT', children });
    this.title = '端末一覧 - ExampleAsset';
    this.readyState = 'complete';
    this.documentElement = new FakeElement({ tagName: 'HTML' });
    this.body = new FakeElement({ tagName: 'BODY' });
    this.scrollingElement = this.documentElement;
  }
}

function createAssetDocument() {
  const selectorCheckbox = new FakeElement({ tagName: 'INPUT', attributes: { type: 'checkbox' } });
  const selectorWrapper = new FakeElement({ id: 'asset-grid_all_select', children: [selectorCheckbox] });
  const selectorHeader = new FakeElement({ tagName: 'TH', id: 'asset-grid___selector__', children: [selectorWrapper] });
  const nameHeader = new FakeElement({
    tagName: 'TH',
    id: 'asset-grid_asset_name',
    attributes: { 'aria-label': '端末名' },
    children: [new FakeElement({ tagName: 'SPAN', className: 'ui-iggrid-headertext', textContent: '端末名' })],
  });
  const mainHeaderRow = new FakeElement({ tagName: 'TR', attributes: { 'data-header-row': '', role: 'row' }, children: [selectorHeader, nameHeader] });
  const mainHeaders = new FakeElement({ id: 'asset-grid_headers', children: [mainHeaderRow] });

  const nameCell = new FakeElement({ tagName: 'TD', textContent: 'HW-001', attributes: { 'aria-describedby': 'asset-grid_asset_name' } });
  const row = new FakeElement({
    tagName: 'TR',
    attributes: { 'data-id': 'row-1', 'aria-selected': 'false' },
    children: [nameCell],
  });
  nameCell.onClick = () => row.setAttribute('aria-selected', 'true');
  const tbody = new FakeElement({ tagName: 'TBODY', children: [row] });
  const mainGrid = new FakeElement({ id: 'asset-grid', children: [tbody] });
  const scroll = new FakeElement({ id: 'asset-grid_scroll', className: 'ui-iggrid-scrolldiv', scrollHeight: 1000, clientHeight: 100, children: [mainGrid] });
  const gridContainer = new FakeElement({ id: 'asset-grid_container', children: [mainHeaders, scroll] });
  const count = new FakeElement({ tagName: 'SPAN', textContent: '全 1 件', attributes: { 'ng-bind': 'assetList.totalCount' } });

  const detailName = new FakeElement({ tagName: 'SPAN', className: 'title-text', textContent: 'HW-001', attributes: { 'ng-bind': 'detail.item.name' } });
  const appTabButton = new FakeElement({ tagName: 'BUTTON', children: [new FakeElement({ tagName: 'SPAN', textContent: 'インストール済みアプリ', attributes: { 'ng-bind': 'tab.label' } })] });
  const appTabItem = new FakeElement({ tagName: 'LI', className: 'active', children: [appTabButton] });
  const tabNav = new FakeElement({ tagName: 'NAV', children: [new FakeElement({ tagName: 'UL', className: 'nav navbar-nav', children: [appTabItem] })] });
  const appHeaders = new FakeElement({
    id: 'app-grid_headers',
    children: ['アプリ名', 'バージョン', '導入日'].map(text => new FakeElement({
      tagName: 'TH',
      children: [new FakeElement({ tagName: 'SPAN', className: 'ui-iggrid-headertext', textContent: text })],
    })),
  });
  const appGrid = new FakeElement({ id: 'app-grid' });
  const radio = new FakeElement({ tagName: 'INPUT', id: 'app-list-radio', attributes: { type: 'radio' }, checked: true });
  const radioLabel = new FakeElement({ tagName: 'LABEL', textContent: 'インストール済みアプリ', attributes: { for: 'app-list-radio' } });
  const csvButton = new FakeElement({ tagName: 'BUTTON', textContent: 'CSV出力' });
  const csvArea = new FakeElement({
    tagName: 'DIV',
    attributes: {
      'data-download-url': "detail.csvUrl['app']",
      'data-before-download': 'detail.beforeAppCsv(param)',
    },
    children: [csvButton],
  });
  const appScope = new FakeElement({ className: 'app-pane', children: [appHeaders, appGrid, radio, radioLabel, csvArea] });
  const frontPanel = new FakeElement({ id: 'detail-panel', children: [detailName, tabNav, appScope] });

  const contents = new FakeElement({ id: 'contents', className: 'asset', children: [gridContainer, count, frontPanel] });
  const breadcrumb = new FakeElement({ id: 'breadcrumb-panel', textContent: '端末一覧' });
  return new FakeDocument([breadcrumb, contents]);
}

function loadDomHelper(document) {
  const context = {
    window: {
      getComputedStyle() { return { display: 'block', visibility: 'visible', opacity: '1' }; },
      setTimeout(callback) { callback(); return 0; },
      scrollY: 0,
      innerHeight: 800,
      scrollTo() {},
      MouseEvent: class {
        constructor(type, options) {
          this.type = type;
          this.options = options || {};
        }
      },
      CSS: { escape(value) { return String(value); } },
    },
    document,
    console,
  };

  vm.createContext(context);
  for (const relativePath of installedAppExportScripts) {
    const source = fs.readFileSync(path.join(root, relativePath), 'utf8');
    vm.runInContext(source, context, { filename: relativePath });
  }
  return context.window.__InstalledAppExportDomHelper;
}

const document = createAssetDocument();
const domHelper = loadDomHelper(document);

assert.ok(domHelper, 'helper should be registered on window.__InstalledAppExportDomHelper');
for (const methodName of [
  'detectAssetPageIdentity',
  'validateAssetPageContract',
  'validateAssetListContract',
  'getAssetListTotalCount',
  'findAssetRowsInfo',
  'clickAssetNameCell',
  'validateClickedRowContext',
  'isDetailPanelReadyFor',
  'clickAppTab',
  'validateAppListContract',
  'clickAppCsvButton',
]) {
  assert.strictEqual(typeof domHelper[methodName], 'function', `${methodName} should be a function`);
}

const identity = domHelper.detectAssetPageIdentity();
assert.strictEqual(identity.scope, 'assetPageIdentity');
assert.strictEqual(identity.ok, true);

const pageContract = domHelper.validateAssetPageContract();
assert.strictEqual(pageContract.scope, 'assetPage');
assert.strictEqual(pageContract.fatalCount, 0);

const listContract = domHelper.validateAssetListContract();
assert.strictEqual(listContract.scope, 'assetList');
assert.strictEqual(listContract.fatalCount, 0);
assert.strictEqual(listContract.details.rowCount, 1);
assert.strictEqual(domHelper.getAssetListTotalCount(), 1);

const rows = domHelper.findAssetRowsInfo();
assert.strictEqual(rows.length, 1);
assert.strictEqual(rows[0].dataId, 'row-1');
assert.strictEqual(rows[0].assetName, 'HW-001');

const clickResult = domHelper.clickAssetNameCell('row-1', 'HW-001');
assert.strictEqual(clickResult.ok, true);
assert.strictEqual(clickResult.action, 'click-asset-name-cell');

const clickedContext = domHelper.validateClickedRowContext('row-1', 'HW-001');
assert.strictEqual(clickedContext.scope, 'clickedRowContext');
assert.strictEqual(clickedContext.fatalCount, 0);
assert.strictEqual(domHelper.isDetailPanelReadyFor('HW-001'), true);

const tabResult = domHelper.clickAppTab();
assert.strictEqual(tabResult.ok, true);
assert.strictEqual(tabResult.action, 'app-tab-already-active');

const appContract = domHelper.validateAppListContract();
assert.strictEqual(appContract.scope, 'appList');
assert.strictEqual(appContract.fatalCount, 0);

const csvResult = domHelper.clickAppCsvButton();
assert.strictEqual(csvResult.ok, true);
assert.strictEqual(csvResult.action, 'click-app-csv-output');
assert.strictEqual(csvResult.clickedText, 'CSV出力');

console.log('InstalledAppExport DOM behavior tests passed.');

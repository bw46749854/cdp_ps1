const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..', '..');
const deviceListExportScripts = [
  'dom/features/device-list-export/contract.js',
  'dom/features/device-list-export/navigation.js',
  'dom/features/device-list-export/export.js',
  'dom/features/device-list-export/index.js',
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
    this.onClick = options.onClick || null;
    this.clickCount = 0;

    for (const child of this.children) {
      child.parentElement = this;
    }
  }

  get textContent() {
    return this._textContent + this.children.map(child => child.textContent).join('');
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
      if (selectors.some(part => matchesSelectorChain(descendant, part, this))) result.push(descendant);
    }
    return [...new Set(result)];
  }

  scrollIntoView() {}

  click() {
    this.clickCount += 1;
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
    this.title = 'ExampleSecurity Cloud Service センサー デバイス (既定グループ)';
    this.readyState = 'complete';
    this.documentElement = new FakeElement({ tagName: 'HTML' });
  }
}

function createDocument() {
  const viewport = new FakeElement({
    id: 'viewport',
    textContent: 'ExampleSecurity Cloud Service センサー デバイス (既定グループ)',
  });
  const sensorNavigation = new FakeElement({
    tagName: 'A',
    textContent: 'センサー',
    attributes: { 'data-components': 'sidenav-item-devices' },
  });
  const deviceDefaultNavigation = new FakeElement({
    tagName: 'SPAN',
    textContent: 'デバイス (既定グループ)',
    attributes: { 'data-label': 'true', 'data-id': '1' },
  });
  const count = new FakeElement({ tagName: 'SPAN', textContent: 'センサー: 1' });

  const exportItem = new FakeElement({ tagName: 'DIV', textContent: 'CSV出力', attributes: { role: 'menuitem' } });
  const wrapper = new FakeElement({ tagName: 'DIV', className: 'ui-menu-item-wrapper', attributes: { role: 'presentation' }, children: [exportItem] });
  const menu = new FakeElement({ tagName: 'DIV', className: 'ui-dropdown-menu', attributes: { role: 'menu' }, children: [wrapper] });
  const taskButton = new FakeElement({
    tagName: 'BUTTON',
    textContent: '操作',
    attributes: { 'aria-haspopup': 'true', role: 'button', 'aria-expanded': 'false' },
  });
  taskButton.onClick = () => taskButton.setAttribute('aria-expanded', 'true');
  const taskRoot = new FakeElement({ className: 'ui-dropdown ui-btn-group', children: [taskButton, menu] });

  exportItem.onClick = () => exportItem.setAttribute('data-clicked', 'true');

  return { document: new FakeDocument([viewport, sensorNavigation, deviceDefaultNavigation, count, taskRoot]), taskButton, exportItem };
}

function loadDomHelper(document) {
  const context = {
    window: {
      getComputedStyle() { return { display: 'block', visibility: 'visible', opacity: '1' }; },
      setTimeout(callback) { callback(); return 0; },
      location: { href: 'https://example.test/devices/default' },
    },
    document,
    console,
  };

  vm.createContext(context);
  for (const relativePath of deviceListExportScripts) {
    const source = fs.readFileSync(path.join(root, relativePath), 'utf8');
    vm.runInContext(source, context, { filename: relativePath });
  }
  return context.window.__DeviceListExportDomHelper;
}

(async () => {
  const fixture = createDocument();
  const domHelper = loadDomHelper(fixture.document);

  assert.ok(domHelper, 'helper should be registered on window.__DeviceListExportDomHelper');
  for (const methodName of [
    'validateExportPageContract',
    'resolveTaskButton',
    'clickTaskButton',
    'isTaskMenuReady',
    'resolveExportMenuItem',
    'clickExportMenuItem',
    'validateExportPostcondition',
  ]) {
    assert.strictEqual(typeof domHelper[methodName], 'function', `${methodName} should be a function`);
  }

  const contract = domHelper.validateExportPageContract();
  assert.strictEqual(contract.scope, 'deviceListExportPage');
  assert.strictEqual(contract.fatalCount, 0);
  assert.strictEqual(contract.details.totalCount, 1);

  const taskButton = domHelper.resolveTaskButton();
  assert.strictEqual(taskButton.ok, true);
  assert.strictEqual(taskButton.count, 1);
  assert.strictEqual(taskButton.menuCount, 1);

  const taskClick = await domHelper.clickTaskButton();
  assert.strictEqual(taskClick.ok, true);
  assert.strictEqual(taskClick.action, 'click-task-button');
  assert.strictEqual(fixture.taskButton.getAttribute('aria-expanded'), 'true');
  assert.strictEqual(fixture.taskButton.clickCount, 1);

  assert.strictEqual(domHelper.isTaskMenuReady(), true);

  const exportItem = domHelper.resolveExportMenuItem();
  assert.strictEqual(exportItem.ok, true);
  assert.strictEqual(exportItem.count, 1);
  assert.strictEqual(exportItem.candidates[0].source, 'role-menuitem');

  const exportClick = await domHelper.clickExportMenuItem();
  assert.strictEqual(exportClick.ok, true);
  assert.strictEqual(exportClick.action, 'click-export');
  assert.strictEqual(fixture.exportItem.getAttribute('data-clicked'), 'true');

  const postcondition = domHelper.validateExportPostcondition();
  assert.strictEqual(postcondition.scope, 'deviceListExportPostcondition');
  assert.strictEqual(postcondition.fatalCount, 0);

  console.log('DeviceListExport DOM behavior tests passed.');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});

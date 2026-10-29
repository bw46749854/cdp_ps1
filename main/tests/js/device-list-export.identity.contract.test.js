const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..', '..');
const scripts = [
  'dom/features/device-list-export/contract.js',
  'dom/features/device-list-export/navigation.js',
  'dom/features/device-list-export/export.js',
  'dom/features/device-list-export/index.js',
];

class FakeElement {
  constructor(options = {}) {
    this.tagName = options.tagName || 'DIV';
    this.id = options.id || '';
    this.className = options.className || '';
    this.textContent = options.textContent || '';
    this.attributes = Object.assign({}, options.attributes || {});
    this.visible = options.visible !== false;
    this.disabled = options.disabled === true;
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
    return Object.prototype.hasOwnProperty.call(this.attributes, name) ? this.attributes[name] : null;
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
}

function createDocument(options = {}) {
  const viewportText = options.includeDeviceDefault === false
    ? 'ExampleSecurity Cloud Service センサー'
    : 'ExampleSecurity Cloud Service センサー デバイス (既定グループ)';
  const viewport = new FakeElement({ id: 'viewport', textContent: viewportText });
  const nav = new FakeElement({
    tagName: 'A',
    textContent: 'センサー',
    attributes: { 'data-components': 'sidenav-item-devices' },
  });

  return {
    readyState: options.readyState || 'loading',
    title: viewportText,
    querySelector(selector) {
      return this.querySelectorAll(selector)[0] || null;
    },
    querySelectorAll(selector) {
      if (selector === '#viewport') return [viewport];
      if (selector === '[data-components="sidenav-item-devices"]') return [nav];
      if (selector === '[class*="Breadcrumb"]' ||
          selector === '[class*="breadcrumb"]' ||
          selector === '[aria-label]' ||
          selector === '[title]' ||
          selector === 'h1' ||
          selector === 'h2' ||
          selector === '.page-title' ||
          selector === '.title') return [];
      return [];
    },
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
    },
    document,
    console,
  };

  vm.createContext(context);
  for (const relativePath of scripts) {
    const source = fs.readFileSync(path.join(root, relativePath), 'utf8');
    vm.runInContext(source, context, { filename: relativePath });
  }

  return context.window.__DeviceListExportDomHelper;
}

const matchingFoundation = loadDomHelper(createDocument({ includeDeviceDefault: true, readyState: 'loading' }));
const matchingIdentity = matchingFoundation.detectDeviceListExportPageIdentity();
assert.strictEqual(matchingIdentity.scope, 'deviceListExportPageIdentity');
assert.strictEqual(matchingIdentity.ok, true, 'identity should match when device default text is present');
assert.strictEqual(matchingIdentity.checks.some(x => x.name === 'page.identity.deviceDefault.text' && x.ok), true, 'identity should require device default text');

const nonMatchingFoundation = loadDomHelper(createDocument({ includeDeviceDefault: false }));
const nonMatchingIdentity = nonMatchingFoundation.detectDeviceListExportPageIdentity();
assert.strictEqual(nonMatchingIdentity.ok, false, 'identity should not match without device default text');
assert.strictEqual(nonMatchingIdentity.checks.some(x => x.name === 'page.identity.deviceDefault.text' && !x.ok), true, 'missing device default text should be a fatal identity check');

console.log('DeviceListExport identity contract tests passed.');

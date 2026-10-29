const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..', '..');

function loadDomHelper(scriptPaths, helperName) {
  const document = {
    title: 'ExampleSecurity Cloud Service',
    readyState: 'complete',
    querySelector() { return null; },
    querySelectorAll() { return []; },
  };
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
  for (const relativePath of scriptPaths) {
    const source = fs.readFileSync(path.join(root, relativePath), 'utf8');
    vm.runInContext(source, context, { filename: relativePath });
  }

  return context.window[helperName];
}

function assertSanitizedContractResult(domHelper, label) {
  const circular = { name: label };
  circular.self = circular;

  const result = domHelper.contractResult('sanitize.test', [
    domHelper.makeCheck('sanitize.circular', true, 'fatal', 'circular details are sanitized', {
      circular,
      fn: function ignoreMe() {},
      sym: Symbol('ignore-me'),
    }),
  ], {
    circular,
    nested: { circular },
    bigintValue: BigInt(42),
  });

  assert.strictEqual(result.ok, true, `${label} result should remain successful`);
  assert.strictEqual(result.checks[0].details.circular.self, '[Circular]', `${label} check details should mark circular references`);
  assert.strictEqual(result.details.circular.self, '[Circular]', `${label} result details should mark circular references`);
  assert.strictEqual(result.details.bigintValue, '42', `${label} bigint details should be stringified`);
  assert.strictEqual(Object.prototype.hasOwnProperty.call(result.checks[0].details, 'fn'), false, `${label} function details should be omitted`);
  assert.strictEqual(Object.prototype.hasOwnProperty.call(result.checks[0].details, 'sym'), false, `${label} symbol details should be omitted`);
  assert.doesNotThrow(() => JSON.stringify(result), `${label} contract result should be JSON serializable`);
}

const deviceListExport = loadDomHelper([
  'dom/features/device-list-export/contract.js',
  'dom/features/device-list-export/navigation.js',
  'dom/features/device-list-export/export.js',
  'dom/features/device-list-export/index.js',
], '__DeviceListExportDomHelper');

const scanTargetSync = loadDomHelper([
  'dom/features/scan-target-sync/contract.js',
  'dom/features/scan-target-sync/list.js',
  'dom/features/scan-target-sync/actions.js',
  'dom/features/scan-target-sync/index.js',
], '__ScanTargetSyncDomHelper');

const installedAppExport = loadDomHelper([
  'dom/features/installed-app-export/contract.js',
  'dom/features/installed-app-export/list.js',
  'dom/features/installed-app-export/detail.js',
  'dom/features/installed-app-export/apps.js',
  'dom/features/installed-app-export/actions.js',
  'dom/features/installed-app-export/index.js',
], '__InstalledAppExportDomHelper');

assertSanitizedContractResult(deviceListExport, 'DeviceListExport');
assertSanitizedContractResult(scanTargetSync, 'ScanTargetSync');
assertSanitizedContractResult(installedAppExport, 'InstalledAppExport');

console.log('DOM contract sanitize tests passed.');

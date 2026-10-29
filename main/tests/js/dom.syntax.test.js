const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..', '..');
const scripts = [
  'dom/features/installed-app-export/contract.js',
  'dom/features/installed-app-export/list.js',
  'dom/features/installed-app-export/detail.js',
  'dom/features/installed-app-export/apps.js',
  'dom/features/installed-app-export/actions.js',
  'dom/features/installed-app-export/index.js',
  'dom/features/scan-target-sync/contract.js',
  'dom/features/scan-target-sync/list.js',
  'dom/features/scan-target-sync/actions.js',
  'dom/features/scan-target-sync/index.js',
  'dom/features/device-list-export/contract.js',
  'dom/features/device-list-export/navigation.js',
  'dom/features/device-list-export/export.js',
  'dom/features/device-list-export/index.js',
];

for (const relativePath of scripts) {
  const fullPath = path.join(root, relativePath);
  const source = fs.readFileSync(fullPath, 'utf8');
  assert.doesNotThrow(() => new vm.Script(source, { filename: relativePath }), `${relativePath} should parse as JavaScript`);
}


const installedAppExportSource = [
  'dom/features/installed-app-export/contract.js',
  'dom/features/installed-app-export/list.js',
  'dom/features/installed-app-export/detail.js',
  'dom/features/installed-app-export/apps.js',
  'dom/features/installed-app-export/actions.js',
  'dom/features/installed-app-export/index.js',
].map(relativePath => fs.readFileSync(path.join(root, relativePath), 'utf8')).join('\n\n');

for (const requiredSymbol of [
  'validateAssetPageContract',
  'validateAssetListContract',
  'findAssetRowsInfo',
  'clickAssetNameCell',
  'validateAppListContract',
  'clickAppCsvButton',
  'sanitizeForReturn',
]) {
  assert.ok(installedAppExportSource.includes(requiredSymbol), `split InstalledAppExport DOM scripts should contain ${requiredSymbol}`);
}

assert.ok(installedAppExportSource.includes('createInstalledAppExportDomHelper'), 'split InstalledAppExport DOM scripts should expose createInstalledAppExportDomHelper');
assert.ok(installedAppExportSource.includes('window.__InstalledAppExportDomHelper = factory(window, document)'), 'split InstalledAppExport DOM scripts should register the browser helper');


const scanTargetSyncSource = [
  'dom/features/scan-target-sync/contract.js',
  'dom/features/scan-target-sync/list.js',
  'dom/features/scan-target-sync/actions.js',
  'dom/features/scan-target-sync/index.js',
].map(relativePath => fs.readFileSync(path.join(root, relativePath), 'utf8')).join('\n\n');

for (const requiredSymbol of [
  'validateDevicePageContract',
  'validateDeviceListContract',
  'prepareOperationContext',
  'findDeviceRowsInfo',
  'syncEndpointCheckbox',
  'validatePostSelectionContract',
  'sanitizeForReturn',
  'hasProductIdentityText',
  'resolveSensorNavigation',
  'buildDevicePageIdentityChecks',
]) {
  assert.ok(scanTargetSyncSource.includes(requiredSymbol), `split scan-target-sync DOM scripts should contain ${requiredSymbol}`);
}

assert.ok(scanTargetSyncSource.includes('createScanTargetSyncDomHelper'), 'split scan-target-sync DOM scripts should expose createScanTargetSyncDomHelper');
assert.ok(scanTargetSyncSource.includes('window.__ScanTargetSyncDomHelper = factory(window, document)'), 'split scan-target-sync DOM scripts should register the browser helper');



const deviceListExportSource = [
  'dom/features/device-list-export/contract.js',
  'dom/features/device-list-export/navigation.js',
  'dom/features/device-list-export/export.js',
  'dom/features/device-list-export/index.js',
].map(relativePath => fs.readFileSync(path.join(root, relativePath), 'utf8')).join('\n\n');

for (const requiredSymbol of [
  'detectDeviceListExportPageIdentity',
  'validateInitialContract',
  'resolveSensorNavigation',
  'resolveDeviceDefaultNavigation',
  'validateExportPageContract',
  'buildIdentityChecks',
  'clickTaskButton',
  'clickExportMenuItem',
]) {
  assert.ok(deviceListExportSource.includes(requiredSymbol), `split device-list-export DOM scripts should contain ${requiredSymbol}`);
}

assert.ok(deviceListExportSource.includes('createDeviceListExportDomHelper'), 'split device-list-export DOM scripts should expose createDeviceListExportDomHelper');
assert.ok(deviceListExportSource.includes('window.__DeviceListExportDomHelper = factory(window, document)'), 'split device-list-export DOM scripts should register the browser helper');

console.log('DOM syntax smoke tests passed.');

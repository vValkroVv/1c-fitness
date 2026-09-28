import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const reports = path.join(root, 'output/20260923_delta_from_20260920/reports/imports');
const output = path.join(root, 'output/20260923_delta_from_20260920');
const require = createRequire(path.join(root, 'end-to-end-xlsx/work/20260923_restore_verified/builder.cjs'));
const { Workbook, SpreadsheetFile } = await import(require.resolve('@oai/artifact-tool'));
const specs = JSON.parse(await fs.readFile(path.join(reports, 'workbook_specs.json'), 'utf8'));
const selectedNames = new Set(process.argv.slice(2));
if (selectedNames.size && [...selectedNames].some(name => !specs.some(spec => spec.name === name))) {
  throw new Error('Unknown workbook name in command arguments');
}
const dates = new Set(['create_date', 'payment_date', 'activation_date', 'end_date']);
const amounts = new Set(['budget', 'price', 'amount_of_payments', 'amount_of_payment', 'payment_left', 'duration', 'freeze', 'guests', 'visits_left', 'count']);
const widths = { client_id: 20, contract_id: 23, service_id: 23, phone: 34, card: 22,
  client_fio: 45, email: 32, funnel: 31, funnel_step: 42, manager: 37, 'филиал': 39,
  contract_name: 70, service_name: 68, type_of_payment: 23 };
function col(index) { let result = ''; for (let n = index + 1; n; n = Math.floor((n - 1) / 26)) result = String.fromCharCode(65 + (n - 1) % 26) + result; return result; }

for (const spec of specs) {
  if (selectedNames.size && !selectedNames.has(spec.name)) continue;
  const book = Workbook.create();
  const sheet = book.worksheets.add('Лист1');
  const last = spec.rows.length + 2;
  const end = col(spec.headers.length - 1);
  const body = spec.rows.map(row => row.map((raw, i) => {
    if (raw === '') return null;
    if (dates.has(spec.headers[i])) return new Date(raw.slice(0, 10) + 'T00:00:00Z');
    if (amounts.has(spec.headers[i])) return Number(raw);
    return raw;
  }));
  sheet.getRange(`A1:${end}${last}`).values = [spec.headers, spec.russian_headers, ...body];
  sheet.getRange(`A1:${end}${last}`).format.font = { name: 'Calibri', size: 11, color: '#000000' };
  sheet.getRange(`A1:${end}2`).format.fill = '#C9DAF8';
  sheet.getRange(`A1:${end}2`).format.font.bold = true;
  sheet.getRange(`A1:${end}2`).format.wrapText = true;
  sheet.getRange(`A1:${end}1`).format.rowHeight = 24;
  sheet.getRange(`A2:${end}2`).format.rowHeight = 60;
  if (spec.rows.length) sheet.getRange(`A3:${end}${last}`).format.rowHeight = 35;
  sheet.freezePanes.freezeRows(2);
  for (let i = 0; i < spec.headers.length; i++) {
    const header = spec.headers[i];
    const letter = col(i);
    sheet.getRange(`${letter}1:${letter}${last}`).format.columnWidth = widths[header] ?? Math.max(18, Math.min(65, Math.max(header.length + 4, (spec.russian_headers[i] || '').length + 2)));
    if (spec.rows.length) {
      const range = sheet.getRange(`${letter}3:${letter}${last}`);
      range.setNumberFormat(dates.has(header) ? 'yyyy-mm-dd' : amounts.has(header) ? '#,##0.##' : '@');
      if (new Set(['client_fio', 'contract_name', 'service_name', 'funnel_step', 'филиал']).has(header)) range.format.wrapText = true;
    }
  }
  book.recalculate();
  const check = await book.inspect({ kind: 'table', range: `Лист1!A1:${col(Math.min(spec.headers.length - 1, 5))}${Math.min(last, 5)}`, include: 'values,formulas', tableMaxRows: 5, tableMaxCols: 6, maxChars: 2000 });
  await fs.writeFile(path.join(reports, spec.name + '.inspect.ndjson'), check.ndjson);
  const preview = await book.render({ sheetName: 'Лист1', range: `A1:${col(Math.min(spec.headers.length - 1, 5))}${Math.min(last, 6)}`, scale: 1.3, format: 'png' });
  await fs.writeFile(path.join(reports, spec.name + '.preview.png'), new Uint8Array(await preview.arrayBuffer()));
  const xlsx = await SpreadsheetFile.exportXlsx(book);
  const destination = path.join(output, spec.name);
  await xlsx.save(destination);
  await fs.rename(destination + '.inspect.ndjson', path.join(reports, spec.name + '.export.inspect.ndjson'));
  console.log(JSON.stringify({ file: spec.name, rows: spec.rows.length }));
}

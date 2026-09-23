import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const work = path.join(root, 'end-to-end-xlsx/work/20260921_phone_dedup_supplement_371');
const output = path.join(root, 'output/20260921_phone_dedup_supplement_371');
const require = createRequire(path.join(work, 'builder.cjs'));
const { Workbook, SpreadsheetFile } = await import(require.resolve('@oai/artifact-tool'));
const specs = JSON.parse(await fs.readFile(path.join(work, 'workbooks.json'), 'utf8'));
await fs.mkdir(output, { recursive: true });
await fs.mkdir(path.join(work, 'previews'), { recursive: true });

function column(index) {
  let result = '';
  for (let n = index + 1; n; n = Math.floor((n - 1) / 26)) result = String.fromCharCode(65 + (n - 1) % 26) + result;
  return result;
}

const dateHeaders = new Set(['create_date', 'payment_date', 'activation_date', 'end_date']);
const moneyHeaders = new Set(['price', 'amount_of_payments', 'amount_of_payment', 'payment_left']);
const textHeaders = new Set(['client_id', 'contract_id', 'service_id', 'phone', 'card', 'client_fio', 'email', 'manager', 'филиал', 'tag', 'funnel', 'funnel_step', 'contract_name', 'service_name', 'name', 'duration_type', 'branches_access', 'type_of_payment']);
const widths = { client_id: 20, contract_id: 23, service_id: 23, phone: 46, card: 22,
  client_fio: 47, email: 32, funnel: 29, funnel_step: 37, manager: 34, 'филиал': 37,
  contract_name: 73, service_name: 68, name: 73, type_of_payment: 22, branches_access: 25 };

const checks = [];
for (const spec of specs) {
  const destination = path.join(output, spec.name);
  try {
    await fs.access(destination);
    if (!process.argv.includes('--replace-generated')) throw new Error(`Refusing to overwrite ${destination}`);
  }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const book = Workbook.create();
  const sheet = book.worksheets.add('Лист1');
  const finalColumn = column(spec.headers.length - 1);
  const lastRow = spec.rows.length + 2;
  const values = spec.rows.map(row => row.map((value, index) => {
    if (value === '') return null;
    return value && dateHeaders.has(spec.headers[index]) ? new Date(value.slice(0, 10) + 'T00:00:00Z') : value;
  }));
  sheet.getRange(`A1:${finalColumn}${lastRow}`).values = [spec.headers, spec.russian_headers, ...values];
  const full = sheet.getRange(`A1:${finalColumn}${lastRow}`);
  full.format.font = { name: 'Calibri', size: 11, color: '#000000' };
  full.format.verticalAlignment = 'center';
  full.format.wrapText = true;
  sheet.getRange(`A1:${finalColumn}2`).format.fill = '#C9DAF8';
  sheet.getRange(`A1:${finalColumn}2`).format.font.bold = true;
  sheet.getRange(`A1:${finalColumn}2`).format.horizontalAlignment = 'center';
  sheet.getRange(`A1:${finalColumn}1`).format.rowHeight = 22;
  sheet.getRange(`A2:${finalColumn}2`).format.rowHeight = 48;
  sheet.freezePanes.freezeRows(2);
  sheet.showGridLines = true;
  for (let i = 0; i < spec.headers.length; i++) {
    const header = spec.headers[i];
    const col = column(i);
    sheet.getRange(`${col}1:${col}${lastRow}`).format.columnWidth = widths[header] ?? 19;
    if (!spec.rows.length) continue;
    const data = sheet.getRange(`${col}3:${col}${lastRow}`);
    if (dateHeaders.has(header)) data.setNumberFormat('yyyy-mm-dd');
    else if (moneyHeaders.has(header)) data.setNumberFormat('#,##0.00');
    else if (textHeaders.has(header)) data.setNumberFormat('@');
    else data.setNumberFormat('General');
    data.format.horizontalAlignment = textHeaders.has(header) ? 'left' : 'right';
  }
  for (let i = 0; i < spec.rows.length; i++) {
    let lines = 1;
    for (let c = 0; c < spec.headers.length; c++) {
      const value = spec.rows[i][c];
      if (typeof value === 'string' && !dateHeaders.has(spec.headers[c])) {
        lines = Math.max(lines, Math.ceil(value.length / ((widths[spec.headers[c]] ?? 19) * 0.85)));
      }
    }
    sheet.getRange(`A${i + 3}:${finalColumn}${i + 3}`).format.rowHeight = Math.max(25, lines * 16 + 8);
  }
  book.recalculate();
  const inspected = await book.inspect({ kind: 'table', range: `Лист1!A1:${column(Math.min(5, spec.headers.length - 1))}${Math.min(lastRow, 5)}`,
    include: 'values,formulas', tableMaxRows: 5, tableMaxCols: 6, maxChars: 2500 });
  checks.push({ file: spec.name, rows: spec.rows.length, inspection: inspected.ndjson });
  const errors = await book.inspect({ kind: 'match', searchTerm: '#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!|#SPILL!|#CALC!',
    options: { useRegex: true, maxResults: 20 }, maxChars: 2000 });
  checks.push({ file: spec.name, errors: errors.ndjson });
  const preview = await book.render({ sheetName: 'Лист1', range: `A1:${column(Math.min(5, spec.headers.length - 1))}${Math.min(lastRow, 6)}`, scale: 1.3, format: 'png' });
  await fs.writeFile(path.join(work, 'previews', spec.name.replace('.xlsx', '.png')), new Uint8Array(await preview.arrayBuffer()));
  const file = await SpreadsheetFile.exportXlsx(book);
  await file.save(destination);
  await fs.rename(destination + '.inspect.ndjson', path.join(work, spec.name + '.inspect.ndjson'));
  console.log(JSON.stringify({ file: spec.name, rows: spec.rows.length }));
}
await fs.writeFile(path.join(work, 'artifact_checks.json'), JSON.stringify(checks, null, 2));

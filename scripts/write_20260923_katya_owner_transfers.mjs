import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'output/20260923_delta_from_20260920');
const reports = path.join(output, 'reports/katya');
const require = createRequire(path.join(root, 'scripts/builder.cjs'));
const { Workbook, SpreadsheetFile } = await import(require.resolve('@oai/artifact-tool'));
const input = JSON.parse(await fs.readFile(path.join(reports, 'owner_transfers_spec.json'), 'utf8'));
if (input.rows.length !== 2) throw new Error('Expected two owner-transfer rows');

const columns = [
  ['review_status', 'Статус'],
  ['old_client_id', 'ID прежнего владельца'],
  ['old_client_fio', 'Прежний владелец'],
  ['new_client_id', 'ID нового владельца'],
  ['new_client_fio', 'Новый владелец'],
  ['contract_id', 'Номер договора'],
  ['contract_name', 'Абонемент'],
  ['subscription_ref', 'Ссылка договора 1С'],
  ['original_sale_date', 'Дата исходной продажи'],
  ['transfer_datetime', 'Дата смены владельца'],
  ['price', 'Цена договора'],
  ['paid_before', 'Оплачено в прежней поставке'],
  ['old_card', 'Карта прежнего владельца'],
  ['new_lead_funnel', 'Воронка нового владельца в 1С'],
  ['action', 'Что проверить'],
];
function col(index) {
  let result = '';
  for (let n = index + 1; n; n = Math.floor((n - 1) / 26)) {
    result = String.fromCharCode(65 + (n - 1) % 26) + result;
  }
  return result;
}

const book = Workbook.create();
const ws = book.worksheets.add('Смена владельца');
const last = input.rows.length + 2;
const end = col(columns.length - 1);
ws.getRange(`A1:${end}${last}`).values = [
  columns.map(([key]) => key),
  columns.map(([, label]) => label),
  ...input.rows.map(row => columns.map(([key]) => row[key] ?? null)),
];
ws.getRange(`A1:${end}${last}`).format.font = { name: 'Calibri', size: 11, color: '#172033' };
ws.getRange(`A1:${end}2`).format.fill = '#D8E5F2';
ws.getRange(`A1:${end}2`).format.font.bold = true;
ws.getRange(`A1:${end}2`).format.wrapText = true;
ws.getRange(`A1:${end}2`).format.rowHeight = 42;
ws.getRange(`A3:${end}${last}`).format.rowHeight = 64;
ws.freezePanes.freezeRows(2);
for (let index = 0; index < columns.length; index++) {
  const [key, label] = columns[index];
  const letter = col(index);
  const maxLength = Math.max(label.length, ...input.rows.map(row => String(row[key] ?? '').length));
  ws.getRange(`${letter}1:${letter}${last}`).format.columnWidth = Math.min(74, Math.max(20, maxLength + 3));
  ws.getRange(`${letter}3:${letter}${last}`).setNumberFormat(
    key === 'price' || key === 'paid_before' ? '#,##0.00' : '@'
  );
  if (['old_client_fio', 'new_client_fio', 'contract_name', 'action'].includes(key)) {
    ws.getRange(`${letter}3:${letter}${last}`).format.wrapText = true;
  }
}

const note = book.worksheets.add('Пояснения');
note.getRange('A1:B6').values = [
  ['Назначение', 'Ручная сверка смены владельца для Кати; не файл импорта'],
  ['Источник', 'Новый backup 23.09 и прежняя поставка из backup 20.09'],
  ['Новых продаж', 'Нет: оба договора куплены до 20.09 и ранее переданы'],
  ['Действие', 'Найти договор в Fitbase и проверить его текущего владельца'],
  ['Запрет повтора', 'Не загружать эти договоры как новые покупки'],
  ['Основание', 'reports/imports/new_client_prior_contract_transfers.csv'],
];
note.getRange('A1:B6').format.font = { name: 'Calibri', size: 11, color: '#172033' };
note.getRange('A1:A6').format.columnWidth = 28;
note.getRange('B1:B6').format.columnWidth = 90;
note.getRange('A1:B1').format.fill = '#D8E5F2';
note.getRange('A1:B1').format.font.bold = true;
note.getRange('B1:B6').format.wrapText = true;
note.getRange('A1:B6').format.rowHeight = 42;
book.recalculate();
await fs.mkdir(reports, { recursive: true });
const preview = await book.render({ sheetName: 'Смена владельца', range: 'A1:H4', scale: 1.3, format: 'png' });
await fs.writeFile(path.join(reports, 'owner_transfers_preview.png'), new Uint8Array(await preview.arrayBuffer()));
const check = await book.inspect({ kind: 'table', range: 'Смена владельца!A1:H4', include: 'values,formulas', tableMaxRows: 4, tableMaxCols: 8, maxChars: 4000 });
await fs.writeFile(path.join(reports, 'owner_transfers.inspect.ndjson'), check.ndjson);
const xlsx = await SpreadsheetFile.exportXlsx(book);
const target = path.join(output, 'Смена_владельца_договора_20260923.xlsx');
await xlsx.save(target);
await fs.rename(target + '.inspect.ndjson', path.join(reports, 'owner_transfers_export.inspect.ndjson'));
console.log(target);

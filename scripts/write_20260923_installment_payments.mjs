import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'output/20260923_delta_from_20260920');
const reports = path.join(output, 'reports/payments');
const require = createRequire(path.join(root, 'scripts/builder.cjs'));
const { Workbook, SpreadsheetFile } = await import(require.resolve('@oai/artifact-tool'));
const source = JSON.parse(await fs.readFile(path.join(reports, 'reconciliation.json'), 'utf8'));

const contracts = new Map(source.contracts.map(row => [row.subscription_ref, row]));
const movements = source.movements;
if (movements.length !== 7 || new Set(movements.map(row => row.contract_id)).size !== 7 ||
    new Set(movements.map(row => row.client_id)).size !== 7 ||
    movements.some(row => String(row.kind) !== '0')) {
  throw new Error('Expected exactly seven distinct payment movements');
}
const total = movements.reduce((sum, row) => sum + Number(row.amount), 0);
if (total !== 31972) throw new Error(`Unexpected payment total: ${total}`);

const headers = [
  'Номер договора', 'ID клиента', 'Клиент', 'Абонемент', 'Дата и время оплаты',
  'Сумма оплаты, ₽', 'Оплачено ранее, ₽', 'Оплачено по backup 23.09, ₽',
  'Долг ранее, ₽', 'Долг по backup 23.09, ₽', 'Проверено в Fitbase', 'Комментарий',
];
const rows = movements.map(movement => {
  const contract = contracts.get(movement.subscription_ref);
  if (!contract || contract.contract_id !== movement.contract_id ||
      contract.client_id !== movement.client_id ||
      Number(contract.paid_delta) !== Number(movement.amount) ||
      contract.review_status !== 'MOVEMENTS_MATCH_DELTA__OLD_SNAPSHOT_NOT_ROW_VERIFIED') {
    throw new Error(`Payment does not match contract reconciliation: ${movement.contract_id}`);
  }
  return [
    String(movement.contract_id), String(movement.client_id), contract.client_fio,
    contract.contract_name, movement.movement_at, Number(movement.amount),
    Number(contract.old_paid), Number(contract.new_paid), Number(contract.old_debt),
    Number(contract.new_debt), null, null,
  ];
});
rows.sort((a, b) => a[4].localeCompare(b[4]) || a[0].localeCompare(b[0]));

const book = Workbook.create();
const sheet = book.worksheets.add('Семь оплат');
sheet.getRange('A1:L8').values = [headers, ...rows];
sheet.getRange('A1:L8').format.font = { name: 'Calibri', size: 11, color: '#172033' };
sheet.getRange('A1:L1').format.fill = '#D8E5F2';
sheet.getRange('A1:L1').format.font.bold = true;
sheet.getRange('A1:L1').format.wrapText = true;
sheet.getRange('A1:L1').format.rowHeight = 48;
sheet.getRange('A2:L8').format.rowHeight = 36;
sheet.getRange('A1:B8').format.columnWidth = 22;
sheet.getRange('C1:C8').format.columnWidth = 38;
sheet.getRange('D1:D8').format.columnWidth = 58;
sheet.getRange('E1:E8').format.columnWidth = 27;
sheet.getRange('F1:J8').format.columnWidth = 27;
sheet.getRange('K1:L8').format.columnWidth = 26;
sheet.getRange('A2:B8').setNumberFormat('@');
sheet.getRange('E2:E8').setNumberFormat('@');
sheet.getRange('F2:J8').setNumberFormat('#,##0.00');
sheet.freezePanes.freezeRows(1);
book.recalculate();

const target = path.join(output, 'Оплаты_рассрочек_20260923.xlsx');
const xlsx = await SpreadsheetFile.exportXlsx(book);
await xlsx.save(target);
await fs.rename(target + '.inspect.ndjson', path.join(reports, 'Оплаты_рассрочек_20260923.xlsx.inspect.ndjson'));
console.log(JSON.stringify({ target, payments: rows.length, total }));

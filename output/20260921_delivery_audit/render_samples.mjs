// Read-only rendering of saved import ranges. Never exports or changes an XLSX.
import fs from 'node:fs/promises';
import path from 'node:path';
import JSZip from 'jszip';
import { SpreadsheetFile } from '@oai/artifact-tool';

const delivery = path.resolve(process.argv[2] || 'output/20260921_final_delivery');
const output = path.resolve(process.argv[4] || path.join('output/20260921_delivery_audit', path.basename(delivery)));
await fs.mkdir(output, { recursive: true });
const ranges = [
  ['fitbase_active_clients_import_zayavki_', ['E1:J7']],
  ['fitbase_active_clients_plastic_cards_', ['A1:C1']],
  ['fitbase_import_abonementy_clientov_', ['F1:M7', 'N1:V7']],
  ['fitbase_import_shablony_abonementov_', ['A1:F7', 'G1:L7']],
  ['fitbase_import_uslugi_clientov_', ['E1:K7', 'L1:Q7']],
  ['fitbase_import_shablony_uslug_', ['A1:I7']],
  ['problem_4_', ['F1:M2', 'N1:V2']],
];
const results = [];
const names = await fs.readdir(delivery);
for (const [prefix, samples] of ranges) {
  if (process.argv[3] && prefix !== process.argv[3]) continue;
  const name = names.find(name => name.startsWith(prefix) && name.endsWith('.xlsx'));
  if (!name) throw new Error(`Missing ${prefix}`);
  // Retain original styles, columns and sampled cell XML. Drop unsampled rows
  // only from the in-memory rendering input to avoid loading millions of cells.
  // The actual audit reads every saved row separately with read_only=True.
  const zip = await JSZip.loadAsync(await fs.readFile(path.join(delivery, name)));
  for (const entry of Object.keys(zip.files).filter(name => /^xl\/worksheets\/sheet\d+\.xml$/.test(name))) {
    const xml = await zip.file(entry).async('string');
    const dataStart = xml.indexOf('<sheetData>');
    const dataEnd = xml.indexOf('</sheetData>');
    const body = xml.slice(dataStart + 11, dataEnd);
    const retained = [];
    for (const match of body.matchAll(/<row\b[^>]*\br="([0-9]+)"[^>]*>[\s\S]*?<\/row>/g)) {
      if (Number(match[1]) > 7) break;
      retained.push(match[0]);
    }
    const sampleRows = retained.join('');
    const clipped = (xml.slice(0, dataStart + 11) + sampleRows + xml.slice(dataEnd))
      .replace(/<dimension ref="([A-Z]+\d+):([A-Z]+)\d+"\s*\/>/, (_, first, last) => `<dimension ref="${first}:${last}7"/>`);
    zip.file(entry, clipped);
  }
  const bytes = await zip.generateAsync({ type: 'uint8array' });
  const workbook = await SpreadsheetFile.importXlsx(bytes);
  const sheets = await workbook.inspect({ kind: 'sheet', include: 'id,name', maxChars: 2000 });
  await fs.writeFile(path.join(output, name.replace('.xlsx', '.sheets.ndjson')), sheets.ndjson);
  const sheetName = prefix === 'problem_4_' ? 'Импорт_абонементы' : 'Лист1';
  for (const range of samples) {
    const preview = await workbook.render({ sheetName, range, scale: 1.5, format: 'png' });
    const filename = `${prefix}${range.replace(':', '-')}.png`;
    await fs.writeFile(path.join(output, filename), new Uint8Array(await preview.arrayBuffer()));
    results.push({ source: name, sheet: sheetName, range, image: filename });
    console.log(`Rendered ${name}: ${range}`);
  }
}
await fs.writeFile(path.join(output, 'visual_samples.json'), JSON.stringify(results, null, 2) + '\n');

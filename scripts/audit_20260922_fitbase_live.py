#!/usr/bin/env python3
"""Read delivered XLSX and UI-downloaded CSV; never connect to or modify Fitbase."""
from pathlib import Path
from collections import Counter
from datetime import date, datetime
import csv
import hashlib
import json
import re
import sqlite3
import argparse
from openpyxl import load_workbook

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/20260922_fitbase_live_audit'
SOURCE = ROOT / 'output/20260921_fitbase_for_customer'

def norm(value):
    if value is None:
        return ''
    if isinstance(value, (date, datetime)):
        return value.strftime('%Y-%m-%d')
    return re.sub(r'\s+', ' ', str(value)).strip()

def read_xlsx(path):
    book = load_workbook(path, read_only=True, data_only=True)
    sheet = book.active
    rows = iter(sheet.values)
    headers = list(next(rows))
    header_count = 1 if 'plastic_cards' in path.name or path.name.startswith('problem_') else 2
    if header_count == 2:
        next(rows)
    data = [{**dict(zip(headers, map(norm, row))), '_xlsx_row': index}
            for index, row in enumerate(rows, header_count + 1)]
    book.close()
    return headers, data

def build_source():
    OUT.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(OUT / 'source.sqlite')
    summary = {}
    patterns = {'leads':'*import_zayavki*', 'cards':'*plastic_cards*',
                'memberships':'fitbase_import_abonementy_clientov*',
                'services':'fitbase_import_uslugi_clientov*',
                'membership_templates':'*shablony_abonementov*',
                'service_templates':'*shablony_uslug*', 'problem4':'problem_4*'}
    for table, pattern in patterns.items():
        path = next(SOURCE.glob(pattern+'.xlsx'))
        headers, rows = read_xlsx(path)
        fields = headers + ['_xlsx_row']
        connection.execute(f'DROP TABLE IF EXISTS "{table}"')
        connection.execute(f'CREATE TABLE "{table}" ({", ".join(chr(34)+h+chr(34)+" TEXT" for h in fields)})')
        connection.executemany(f'INSERT INTO "{table}" VALUES ({",".join("?" for _ in fields)})',
                               [[row[h] for h in fields] for row in rows])
        stats = {'file':path.name, 'rows':len(rows), 'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
        for field in ['филиал', 'funnel', 'tag', 'manager']:
            if field in headers:
                stats[field] = dict(Counter(row[field] for row in rows))
        if table == 'leads':
            stats['branch_funnel'] = dict(Counter(row['филиал']+' | '+row['funnel'] for row in rows))
        if table == 'memberships':
            stats['contract_rows'] = sum(bool(row['contract_id']) for row in rows)
            stats['clients'] = len({row['client_id'] for row in rows})
        summary[table] = stats
        print(table, len(rows), flush=True)
    connection.commit()
    connection.close()
    (OUT/'source_summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n')
    return summary

def phone_tokens(value):
    tokens = []
    for item in re.split(r'[,;]', value):
        digits = re.sub(r'\D', '', item)
        if len(digits) == 11 and digits[0] == '8':
            digits = '7' + digits[1:]
        if len(digits) == 10:
            digits = '7' + digits
        if digits:
            tokens.append(digits)
    return tuple(tokens)

def compare_leads():
    connection = sqlite3.connect(OUT / 'source.sqlite')
    connection.row_factory = sqlite3.Row
    sources = [dict(row) for row in connection.execute('SELECT * FROM leads')]
    assignments = {
        'leads_gogolevsky_active.csv': ('Гоголевский', 'Действующие абонементы', ''),
        'leads_gogolevsky_reactivation_peuna.csv': ('Гоголевский', 'Реактивация', 'Пеуна Анастасия Ивановна'),
        'leads_gogolevsky_reactivation_pilia.csv': ('Гоголевский', 'Реактивация', 'Пилия Анастасия Артуровна'),
        'leads_gogolevsky_reactivation_efremova.csv': ('Гоголевский', 'Реактивация', 'Ефремова Алена'),
        'leads_industrial_active.csv': ('Промышленная', 'Действующие абонементы', ''),
        'leads_industrial_reactivation.csv': ('Промышленная', 'Реактивация', ''),
        'leads_rovio_active.csv': ('Ровио', 'Действующие абонементы', ''),
        'leads_rovio_reactivation.csv': ('Ровио', 'Реактивация', ''),
        'leads_stolitsa_active.csv': ('Столица', 'Действующие абонементы', ''),
        'leads_stolitsa_reactivation.csv': ('Столица', 'Реактивация', ''),
    }
    reports, details = [], []
    for filename, (club, funnel, manager) in assignments.items():
        path = OUT/'downloads'/filename
        if not path.exists():
            continue
        source = [r for r in sources if r['филиал'] == f'Фитнес Империя ({club})'
                  and r['funnel'] == funnel and (not manager or r['manager'] == manager)]
        with path.open(encoding='utf-8-sig', newline='') as handle:
            live = list(csv.DictReader(handle, delimiter=';'))
        by_name, by_phone = {}, {}
        for row in source:
            by_name.setdefault(norm(row['client_fio']), []).append(row)
            for phone in phone_tokens(row['phone']):
                by_phone.setdefault(phone, []).append(row)
        matched, counts = Counter(), Counter()
        missing, unmatched = [], []
        for line, row in enumerate(live, 2):
            name, phones = norm(row['Клиент']), phone_tokens(row['Телефон'])
            name_candidates = by_name.get(name, [])
            phone_candidates = {r['client_id']:r for p in phones for r in by_phone.get(p, [])}
            joint = [r for r in name_candidates if r['client_id'] in phone_candidates]
            candidates = joint or (name_candidates if len(name_candidates) == 1 else list(phone_candidates.values()))
            if len(candidates) != 1:
                counts['unmatched_live_count'] += 1
                unmatched.append({'csv_row':line, 'live':row})
                continue
            expected = candidates[0]
            matched[expected['client_id']] += 1
            differences = {}
            for source_field, live_field in [('client_fio','Клиент'), ('manager','Менеджер'), ('email','Email'),
                    ('funnel','Название воронки'), ('funnel_step','Этап воронки'), ('budget','Бюджет')]:
                if norm(expected[source_field]) != norm(row[live_field]):
                    differences[source_field] = {'source':expected[source_field], 'live':row[live_field]}
                    counts[source_field+'_mismatch'] += 1
            live_date = datetime.strptime(row['Дата создания'], '%d.%m.%Y %H:%M').strftime('%Y-%m-%d')
            if live_date != expected['create_date']:
                differences['create_date'] = {'source':expected['create_date'], 'live':live_date}
                counts['create_date_mismatch'] += 1
            source_phones = phone_tokens(expected['phone'])
            if set(phones) != set(source_phones):
                field = 'phone_subset' if phones and set(phones) < set(source_phones) else 'phone_mismatch'
                counts[field] += 1
                differences[field] = {'source':expected['phone'], 'live':row['Телефон']}
            if differences:
                details.append({'file':filename, 'csv_row':line, 'client_id':expected['client_id'],
                                'client_fio':expected['client_fio'], '_xlsx_row':expected['_xlsx_row'],
                                'differences':differences})
            else:
                counts['all_exported_fields_equal'] += 1
        for row in source:
            if row['client_id'] not in matched:
                missing.append(row)
        reports.append({'file':filename, 'club':club, 'funnel':funnel, 'manager':manager,
                        'source_rows':len(source), 'live_rows':len(live), 'matched_unique_clients':len(matched),
                        'missing_source_clients':missing, 'unmatched_live':unmatched,
                        'duplicate_mapped_rows':sum(v-1 for v in matched.values()), **counts})
    (OUT/'lead_reconciliation.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2)+'\n')
    (OUT/'lead_differences.json').write_text(json.dumps(details,ensure_ascii=False,indent=2)+'\n')
    for report in reports:
        brief = {k:v for k,v in report.items() if k not in ['missing_source_clients','unmatched_live']}
        brief['missing_source_clients'] = len(report['missing_source_clients'])
        brief['unmatched_live'] = len(report['unmatched_live'])
        print(json.dumps(brief,ensure_ascii=False))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compare-leads', action='store_true')
    args = parser.parse_args()
    if args.compare_leads:
        compare_leads()
    else:
        print(json.dumps(build_source(), ensure_ascii=False, indent=2))

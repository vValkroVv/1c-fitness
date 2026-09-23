#!/usr/bin/env python3
"""Reconcile downloaded UI exports without network access or source changes."""
import csv
import json
import re
import sqlite3
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/20260922_fitbase_live_audit'

def norm(v):
    return re.sub(r'\s+', ' ', str(v or '')).strip()

def phones(v):
    result = set()
    for part in re.split('[,;]', v):
        p = re.sub(r'\D', '', part)
        if len(p) == 10:
            p = '7' + p
        if len(p) == 11 and p.startswith('8'):
            p = '7' + p[1:]
        if p:
            result.add(p)
    return result

def dump(name, data):
    (OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')

def reconcile():
    db = sqlite3.connect(OUT / 'source.sqlite')
    db.row_factory = sqlite3.Row
    source = [dict(r) for r in db.execute('select * from leads')]
    old = json.loads((OUT / 'lead_reconciliation.json').read_text())
    reports, differences, mappings = [], [], []
    for part in old:
        src = [r for r in source if r['филиал'] == f"Фитнес Империя ({part['club']})"
               and r['funnel'] == part['funnel']
               and (not part['manager'] or r['manager'] == part['manager'])]
        live = list(csv.DictReader((OUT/'downloads'/part['file']).open(encoding='utf-8-sig'), delimiter=';'))
        for r in live:
            r['_date'] = datetime.strptime(r['Дата создания'], '%d.%m.%Y %H:%M').strftime('%Y-%m-%d')
        by_name, by_phone = defaultdict(set), defaultdict(set)
        for i, r in enumerate(src):
            by_name[norm(r['client_fio'])].add(i)
            for p in phones(r['phone']):
                by_phone[p].add(i)
        remaining_s, remaining_l = set(range(len(src))), set(range(len(live)))
        pairs = []
        # Each pass requires a unique candidate in BOTH directions. Dates and
        # managers disambiguate namesakes; the match basis stays in the report.
        methods = ['name_phone_date_manager', 'name_phone', 'name_date_manager',
                   'phone_date_manager', 'unique_name', 'unique_phone',
                   'name_yo_date_manager', 'phone_leading_zero_date_manager']
        for method in methods:
            while True:
                candidates = {}
                reverse = Counter()
                for j in remaining_l:
                    r = live[j]
                    ns = by_name.get(norm(r['Клиент']), set()) if norm(r['Клиент']) else set()
                    ps = set().union(*(by_phone.get(p, set()) for p in phones(r['Телефон'])))
                    if method == 'name_yo_date_manager':
                        ids = {i for i in remaining_s if norm(src[i]['client_fio']).replace('ё','е')
                               == norm(r['Клиент']).replace('ё','е')}
                    elif method == 'phone_leading_zero_date_manager':
                        lp = {p.lstrip('0') for p in phones(r['Телефон'])}
                        ids = {i for i in remaining_s if lp and lp &
                               {p.lstrip('0') for p in phones(src[i]['phone'])}}
                    elif method.startswith('name_phone'):
                        ids = ns & ps
                    elif method in ('name_date_manager', 'unique_name'):
                        ids = ns
                    else:
                        ids = ps
                    ids = ids & remaining_s
                    if method.endswith('date_manager'):
                        ids = {i for i in ids if src[i]['create_date'] == r['_date']
                               and norm(src[i]['manager']) == norm(r['Менеджер'])}
                    candidates[j] = ids
                    reverse.update(ids)
                accepted = [(next(iter(ids)), j, method) for j, ids in candidates.items()
                            if len(ids) == 1 and reverse[next(iter(ids))] == 1]
                if not accepted:
                    break
                for i, j, basis in accepted:
                    pairs.append((i, j, basis)); remaining_s.remove(i); remaining_l.remove(j)
        counts = Counter()
        for i, j, basis in pairs:
            s, r = src[i], live[j]
            diff = {}
            for sf, lf in [('client_fio', 'Клиент'), ('manager', 'Менеджер'), ('email', 'Email'),
                           ('funnel', 'Название воронки'), ('funnel_step', 'Этап воронки'), ('budget', 'Бюджет')]:
                if norm(s[sf]) != norm(r[lf]):
                    diff[sf] = {'source': s[sf], 'live': r[lf]}
            if s['create_date'] != r['_date']:
                diff['create_date'] = {'source': s['create_date'], 'live': r['_date']}
            sp, lp = phones(s['phone']), phones(r['Телефон'])
            if sp != lp:
                key = 'phone_subset' if lp and lp < sp else 'phone_mismatch'
                diff[key] = {'source': s['phone'], 'live': r['Телефон']}
            item = {'file': part['file'], 'csv_row': j+2, 'client_id': s['client_id'],
                    'client_fio': s['client_fio'], '_xlsx_row': s['_xlsx_row'], 'match_basis': basis}
            mappings.append(item)
            counts.update(diff.keys())
            if diff:
                differences.append({**item, 'differences': diff})
            else:
                counts['all_exported_fields_equal'] += 1
        reports.append({'file': part['file'], 'club': part['club'], 'funnel':part['funnel'],
                        'source_rows':len(src), 'live_rows':len(live), 'matched_one_to_one':len(pairs),
                        'match_basis':dict(Counter(p[2] for p in pairs)), 'counts':dict(counts),
                        'unmatched_source':[src[i] for i in sorted(remaining_s)],
                        'unmatched_live':[{'csv_row':j+2, **live[j]} for j in sorted(remaining_l)]})
    dump('lead_reconciliation_final.json', reports)
    dump('lead_differences_final.json', differences)
    dump('lead_mapping_final.json', mappings)
    print(json.dumps({'source':sum(x['source_rows'] for x in reports),
        'live':sum(x['live_rows'] for x in reports),
        'matched':len(mappings), 'counts':dict(sum((Counter(x['counts']) for x in reports),Counter())),
        'unmatched_source':sum(len(x['unmatched_source']) for x in reports),
        'unmatched_live':sum(len(x['unmatched_live']) for x in reports)},ensure_ascii=False))
    for r in reports:
        print(r['file'], [(s['client_id'],s['client_fio'],s['phone']) for s in r['unmatched_source']],
              'live',len(r['unmatched_live']))

if __name__ == '__main__':
    reconcile()

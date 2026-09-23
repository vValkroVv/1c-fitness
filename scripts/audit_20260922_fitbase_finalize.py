#!/usr/bin/env python3
"""Build audit indexes and metrics from saved evidence, without network access."""
import csv
import json
import re
import sqlite3
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/20260922_fitbase_live_audit'

def read(name):
    return json.loads((OUT / name).read_text())

def write(name, data):
    (OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')

def csv_write(name, rows):
    if not rows:
        return
    with (OUT / name).open('w', encoding='utf-8-sig', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

def main():
    reports = read('lead_reconciliation_final.json')
    diffs = read('lead_differences_final.json')
    mapping = read('lead_mapping_final.json')
    contacts = read('contact_identity_diagnostics.json')
    catalog = read('catalog_reconciliation_final.json')
    db = sqlite3.connect(OUT / 'source.sqlite')
    db.row_factory = sqlite3.Row
    assert len({(r['file'], r['csv_row']) for r in mapping}) == len(mapping)
    assert len({r['client_id'] for r in mapping}) == len(mapping)
    grouped = next(r for r in reports if r['file']=='leads_stolitsa_reactivation.csv')
    assert {r['client_id'] for r in grouped['unmatched_source']} == {'000002642','000029130'}
    assert len(grouped['unmatched_live']) == 2
    assert {r['Клиент'] for r in grouped['unmatched_live']} == {'Васильева Мария Александровна'}
    assert {r['Телефон'] for r in grouped['unmatched_live']} == {'79114347277'}
    missing = [{**r, 'export':part['file']} for part in reports for r in part['unmatched_source']
               if r['client_id'] not in {'000002642','000029130'}]
    assert len(missing) == 11 and all(not r['phone'] for r in missing)
    csv_write('missing_leads_final.csv', missing)
    issue_rows = []
    for r in diffs:
        for field, values in r['differences'].items():
            issue_rows.append({k:r[k] for k in ['file','csv_row','client_id','client_fio','_xlsx_row','match_basis']}
                              | {'field':field, 'source':values['source'], 'live':values['live']})
    csv_write('lead_field_differences_final.csv', issue_rows)
    risks = [r for r in contacts if any(x['client_id'] != r['client_id'] for x in r['live_phone_source_clients'])]
    csv_write('homonym_contact_risks.csv', [{
        'source_client_id':r['client_id'], 'client_fio':r['client_fio'], 'file':r['file'],
        'csv_row':r['csv_row'], 'xlsx_row':r['_xlsx_row'],
        'expected_phone':r['differences']['phone_mismatch']['source'],
        'live_phone':r['differences']['phone_mismatch']['live'],
        'other_source_ids':','.join(x['client_id'] for x in r['live_phone_source_clients'])} for r in risks])
    price_rows = [{'kind':'membership', 'url':'https://fitnes-imperiya.fitbase.io'+r['url'],
                   'name':r['name'], 'source_price':r['source_price'], 'live_prices':str(r['live_prices'])}
                  for r in catalog['membership_price_differences']]
    price_rows += [{'kind':'service','url':'https://fitnes-imperiya.fitbase.io'+r['url'],
                    'name':r['name'],'source_price':r['source'],'live_prices':str(r['live'])}
                   for r in catalog['service_price_differences']]
    csv_write('catalog_price_differences_final.csv',price_rows)
    service_counts = Counter()
    for row in catalog['service_templates'].values():
        service_counts[row['cells'][-8]] += int(re.search(r'Всего: (\d+)',row['cells'][-4])[1])
    source_service_counts = Counter(dict(db.execute('select service_name,count(*) from services group by service_name')))
    write('service_count_reconciliation.json', {
        'source':dict(source_service_counts), 'live_catalog':dict(service_counts),
        'differences':[{'name':name,'source':source_service_counts[name],'live':service_counts[name]}
                       for name in sorted(service_counts.keys() | source_service_counts.keys())
                       if service_counts[name] != source_service_counts[name]],
        'one_time_source_rows':[dict(r) for r in db.execute("select * from services where service_name='Разовое посещение'")]
    })
    names = ['Смирнова Екатерина Анатольевна','Васильева Мария Александровна',
             'Анхимова Елена Александровна','Михеева Наталья Александровна']
    write('homonym_source_rows.json', {name:{t:[dict(r) for r in db.execute(
        f'select * from {t} where {"фио" if t == "cards" else "client_fio"}=?',(name,))] for t in ['leads','memberships','cards','services']}
        for name in names})
    blank_names = Counter(r['file'] for r in diffs if 'client_fio' in r['differences']
                          and not r['differences']['client_fio']['live'])
    stats = {
        'source_leads':sum(r['source_rows'] for r in reports),
        'live_leads':sum(r['live_rows'] for r in reports),
        'one_to_one_matches':len(mapping), 'group_matched_rows':2, 'missing_leads':len(missing),
        'field_counts':dict(sum((Counter(r['counts']) for r in reports),Counter())),
        'blank_client_name_rows':sum(blank_names.values()), 'blank_client_name_by_export':dict(blank_names),
        'homonym_phone_risk_rows':len(risks),
        'homonym_phone_risk_active_rows':sum('_active' in r['file'] for r in risks),
        'email_missing_in_export':sum('email' in r['differences'] and not r['differences']['email']['live'] for r in diffs),
        'membership_template_ids':len(catalog['membership_templates']),
        'membership_catalog_purchases':sum(int(re.search(r'Всего: (\d+)',r['cells'][7])[1])
            for r in catalog['membership_templates'].values()),
        'service_template_ids':len(catalog['service_templates']),
        'service_catalog_purchases':sum(int(re.search(r'Всего: (\d+)',r['cells'][-4])[1])
            for r in catalog['service_templates'].values()),
        'membership_price_differences':len(catalog['membership_price_differences']),
        'membership_price_under_100_instead_of_at_least_1000':sum(
            r['live_prices'] and max(r['live_prices'])<100 and float(r['source_price'])>=1000
            for r in catalog['membership_price_differences']),
        'service_price_differences':len(catalog['service_price_differences']),
        'test_service_purchases':service_counts['тест'],
        'service_purchases_excluding_test':sum(service_counts.values())-service_counts['тест'],
        'missing_exact_membership_names':catalog['missing_exact_membership_names'],
        'missing_exact_service_names':catalog['missing_exact_service_names'],
        'problem4_imported':False,
    }
    assert stats['source_leads'] - stats['live_leads'] == stats['missing_leads']
    assert stats['one_to_one_matches'] + stats['group_matched_rows'] == stats['live_leads']
    write('audit_metrics.json',stats)
    print(json.dumps(stats,ensure_ascii=False,indent=2))

if __name__ == '__main__':
    main()

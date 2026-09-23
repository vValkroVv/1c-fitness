#!/usr/bin/env python3
"""Copy the verified delivery while omitting its supplemental contract history."""

import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "output/20260921_final_v2_delivery"
TARGET = ROOT / "output/20260921_final_v2_delivery_without_excluded_history"
AUDIT = ROOT / "output/20260921_package_comparison"
REMOVED = {
    "reports/membership_coverage/changed_clients_evidence.json",
    "reports/membership_coverage/excluded_history.csv",
    "reports/membership_coverage/explanation.md",
    "reports/membership_coverage/summary.json",
}
EDITED = {"README.md", "reports/business_notes.md", "reports/final_report.md"}
OPEN_QUESTIONS = (
    "Открытые вопросы перед импортом соответствующих строк: у договора 154220 "
    "в XLSX пустой остаток САЙКЛ, а в другой аналитике регистра получается 9; "
    "у договора 144499 название содержит 36 месяцев, но документ и даты "
    "соответствуют 12 месяцам. Эти вопросы ранее переданы пользователю; "
    "упаковка без истории не меняет значения договоров."
)


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def replace_section(text, heading, replacement):
    expression = re.escape(heading) + r"\n.*?(?=\n## |\Z)"
    result, count = re.subn(expression, replacement.rstrip() + "\n", text, flags=re.S)
    if count != 1:
        raise ValueError(f"Expected exactly one section: {heading}")
    return result


def main():
    if TARGET.exists():
        raise ValueError("The destination already exists; refusing to overwrite it")
    before = {str(p.relative_to(SOURCE)): digest(p) for p in SOURCE.rglob("*") if p.is_file()}
    assert len(before) == 43 and REMOVED <= before.keys()
    TARGET.mkdir()
    for name in sorted(before.keys() - REMOVED):
        destination = TARGET / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SOURCE / name, destination)

    path = TARGET / "README.md"
    text = replace_section(path.read_text(), "## Дополнительная история по решению пользователя", """
## Вариант без отдельного отчёта об истории

По новому запросу пользователя из этого комплекта удалён отдельный отчёт
об исключённой истории 766 клиентов и сопровождающие его три файла.
Все 766 клиентов остаются в заявках. Семь XLSX и фотоархив точно совпадают
с исходной поставкой, их данные и единый срез не менялись.
""".strip())
    text = text.replace(
        "**Problem4:** договор 151350 передан отдельно для согласованного ручного\nразбора остатка посещений. Договор не продублирован в основном файле абонементов.",
        "**Problem4:** договор 151350 сохранён отдельно по плану и не продублирован\nв основном файле. На сентябрьском срезе он завершён, остаток посещений равен 0.",
    )
    path.write_text(text + "\n" + OPEN_QUESTIONS + "\n", encoding="utf-8")

    path = TARGET / "reports/business_notes.md"
    text = replace_section(path.read_text(), "## История клиентов без строк абонементов", """
## Состав варианта без истории

Отдельный отчёт об исключённой истории и его вспомогательные файлы удалены
по новому запросу пользователя. Правила импорта сохранены; 766 клиентов
остаются в заявках. Сами XLSX и фотоархив не менялись.
""".strip())
    text = replace_section(text, "## Согласованное исключение problem4", """
## Согласованное исключение problem4

Договор 151350 выделен из текущего сентябрьского набора ровно один раз,
из основного файла убран. Он закончился 03.07.2026; остаток посещений
на текущем срезе равен 0. Отдельный файл сохранён по требованию плана.
""".strip())
    path.write_text(text + "\n## Открытые вопросы\n\n" + OPEN_QUESTIONS + "\n", encoding="utf-8")

    path = TARGET / "reports/final_report.md"
    text = path.read_text()
    text = text.replace("**Поставка готова.** Полный pipeline и независимые проверки завершены с PASS.",
                        "**Вариант без отдельного отчёта об истории.** Технические проверки исходной поставки завершены с PASS.")
    text = text.replace("output/20260921_final_v2_delivery/", "output/20260921_final_v2_delivery_without_excluded_history/")
    text = text.replace("output/20260921_fitbase_customer_delivery.zip", "output/20260921_fitbase_customer_delivery_without_excluded_history.zip")
    start = text.index("**История 766 клиентов реактивации:**")
    end = text.index("**Шаблоны:**", start)
    text = text[:start] + (
        "**Дополнительная история:** отдельный отчёт и его вспомогательные файлы\n"
        "удалены по новому запросу пользователя. Все 766 клиентов остаются\n"
        "в заявках, состав основного импорта сохранён.\n\n"
    ) + text[end:]
    text = text.replace("Семантика остатка посещений требует прежнего согласованного ручного разбора.",
                        "На сентябрьском срезе договор завершён, остаток посещений равен 0.")
    text = text.replace("согласованный CSV истории и контрольные отчёты.", "контрольные отчёты без дополнительной истории.")
    path.write_text(text + "\n## Открытые вопросы\n\n" + OPEN_QUESTIONS + "\n", encoding="utf-8")

    after = {str(p.relative_to(TARGET)): digest(p) for p in TARGET.rglob("*") if p.is_file()}
    assert before.keys() - after.keys() == REMOVED and not (after.keys() - before.keys())
    changed = {name for name in after if after[name] != before[name]}
    assert changed == EDITED
    for name in before:
        assert digest(SOURCE / name) == before[name], f"Original changed: {name}"
    manifest = json.loads((TARGET / "reports/delivery_manifest.json").read_text())
    for entry in manifest["files"]:
        assert after[entry["name"]] == entry["sha256"]
    for name in EDITED:
        text = (TARGET / name).read_text()
        assert "reports/membership_coverage/" not in text
        assert "excluded_history.csv" not in text
    result = {
        "status": "PASS", "before_directory": str(SOURCE), "after_directory": str(TARGET),
        "before_files": len(before), "after_files": len(after),
        "removed": sorted(REMOVED), "changed_documentation": sorted(changed),
        "byte_identical_retained_files": len(after) - len(changed),
        "unchanged_payload_files": len(manifest["files"]),
        "before_sha256": before, "after_sha256": after,
    }
    AUDIT.mkdir(parents=True, exist_ok=True)
    (AUDIT / "comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: v for k, v in result.items() if not k.endswith("_sha256")}, ensure_ascii=False))


if __name__ == "__main__":
    main()

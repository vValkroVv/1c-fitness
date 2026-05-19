# Part 2 start

Date: 2026-05-19
Workspace: `/root/workspace/1c-fitness`

Goal: rebuild 1C Fitness -> Fitbase pipeline for three funnels:

- Действующие клиенты
- Новые заявки
- Реактивация

Baseline cutoff: `2026-04-29`
Shift experiment: Friday `2026-04-24` -> Monday `2026-04-27`

Baseline artifacts copied to `output/archive_before_part2/`.

Runtime check:

- database: `FitnessRestored`
- state: `ONLINE`
- user tables: `2503`
- actual container image observed during this run: `mcr.microsoft.com/mssql/server:2022-latest`

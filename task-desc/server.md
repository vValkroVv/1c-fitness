# Сервер

Проверено 2026-05-04. Подключение выполнено по SSH к `linuxadmin@192.168.2.36` через VPN `fitness`; маршрут до сервера шел через `ppp0`:

- gateway: `192.168.101.254`
- interface: `ppp0`

## Что за сервер

- hostname: `u26`
- пользователь: `linuxadmin`
- рабочая папка после входа: `/home`
- kernel: `Linux u26 7.0.0-15-generic #15-Ubuntu SMP PREEMPT_DYNAMIC Wed Apr 22 16:06:43 UTC 2026 x86_64 GNU/Linux`

## RAM

По `free -h`:

```text
Mem:   total 30Gi, used 1.1Gi, free 16Gi, buff/cache 12Gi, available 29Gi
Swap:  total 8.0Gi, used 0B, free 8.0Gi
```

По `/proc/meminfo`:

```text
MemTotal:     31,765,012 kB
MemAvailable: 30,627,148 kB
SwapTotal:     8,388,604 kB
SwapFree:      8,388,604 kB
```

Итого по RAM: примерно `30 GiB` оперативной памяти, из них доступно примерно `29 GiB`.

## Диск и место

`/home` находится на том же разделе, что и `/`:

```text
Filesystem                        Type  Size  Used Avail Use% Mounted on
/dev/mapper/ubuntu--vg-ubuntu--lv ext4   48G   23G   23G  51% /
```

Блочные устройства:

```text
NAME                       SIZE TYPE FSTYPE      MOUNTPOINTS
sda                        100G disk
├─sda1                       1M part
├─sda2                       2G part ext4        /boot
└─sda3                      98G part LVM2_member
  └─ubuntu--vg-ubuntu--lv   49G lvm  ext4        /
sr0                       1024M rom
```

Итого по диску:

- физический диск: `100G`
- корневой filesystem, где лежит `/home`: `48G`
- занято на `/`: `23G`
- свободно на `/`: `23G`
- `/boot`: `2.0G`, свободно `1.7G`

Важно: файл на 12G уже лежит внутри `/home`, поэтому для обработки без дополнительных настроек реально ориентироваться на свободные `23G` на текущем filesystem.

## Что лежит в `/home`

В `/home` есть один пользовательский каталог:

```text
/home/linuxadmin
```

Основной большой файл:

```text
/home/linuxadmin/Fitnes.bak
```

Параметры файла:

- размер: `12,770,610,688` bytes
- примерный размер: `11.9 GiB` / `12.8 GB`
- `ls -lh` показывает: `12G`
- `du -h` показывает: `12G`
- владелец: `linuxadmin:linuxadmin`
- права: `-rw-rw-r--`
- дата изменения: `2026-04-29 20:57:02 +0000`
- тип по `file`: `data`

Топ файлов в `/home`:

```text
12GB    /home/linuxadmin/Fitnes.bak
3.7KB   /home/linuxadmin/.bashrc
807B    /home/linuxadmin/.profile
220B    /home/linuxadmin/.bash_logout
46B     /home/linuxadmin/.bash_history
```

Итого: на сервере есть backup-файл `Fitnes.bak` около 12G, RAM достаточно много (`30 GiB` всего, `29 GiB` доступно), а свободного места на текущем разделе `/home` около `23G`.

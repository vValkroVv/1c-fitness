## Подключение к серверу

Перед подключением должен быть активен VPN `fitness`.

Важная деталь, проверено 2026-07-05: на macOS может быть несколько VPN-интерфейсов.
Для этого сервера рабочий SSH идет через PPP-интерфейс `ppp0` с локальным адресом
`192.168.101.201`. Если подключаться без явной привязки к этому адресу, маршрут
может уйти через другой `utun`-интерфейс; тогда TCP-порт `22` открывается, но
SSH-сессия сбрасывается до аутентификации с ошибкой:

```text
kex_exchange_identification: read: Connection reset by peer
Connection reset by 192.168.2.36 port 22
```

Проверить интерфейс:

```sh
ifconfig ppp0
route get "$IP"
```

Подключаться так:

```sh
set -a; . ./.env; set +a
ssh -b 192.168.101.201 "$LOGIN@$IP"
```

Когда SSH попросит пароль, используй значение `PASS` из `.env`.

Пример скачивания backup через тот же интерфейс:

```sh
set -a; . ./.env; set +a
rsync --partial --append --progress \
  -e "ssh -b 192.168.101.201 -o StrictHostKeyChecking=accept-new" \
  "$LOGIN@$IP:/home/linuxadmin/Fitnes.bak" \
  data/Fitnes-30-06-26.bak
```

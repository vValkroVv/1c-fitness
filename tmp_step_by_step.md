# Step-by-step VPN route and SSH check

Date: 2026-05-04

Goal: make SSH traffic to the server from `.env` go through the `fitness` L2TP VPN, then verify SSH login.

Notes:
- `.env` contains `IP`, `LOGIN`, and `PASS`.
- The password was read from `.env` only by the shell/expect process. It is not written here.
- Target IP used during the check: `192.168.2.36`.

## 1. Checked available VPN connections

```sh
scutil --nc list
```

Relevant result:

```text
* (Connected) ... "v2RayTun"
* (Connected) ... "fitness" [PPP:L2TP]
```

## 2. Found the `fitness` PPP interface

```sh
for i in $(ifconfig | awk '/^ppp[0-9]+:/{gsub(":","",$1); print $1}'); do
  printf '### %s\n' "$i"
  ifconfig "$i" | awk '/inet /{print}'
done
```

Result:

```text
### ppp0
inet 192.168.101.201 --> 192.168.101.254 netmask 0xffffff00
```

So `fitness` is `ppp0`, and its peer/gateway is `192.168.101.254`.

## 3. Checked current route to the target server

```sh
set -a
. ./.env
set +a

route -n get "$IP" | egrep 'route to|destination|gateway|interface|ifscope'
```

Initial result:

```text
route to: 192.168.2.36
destination: default
interface: utun7
```

This meant traffic to the target server was not going through `fitness`.

## 4. Tried non-interactive sudo route update

```sh
set -a
. ./.env
set +a

VPN_IF=ppp0
VPN_GW=$(ifconfig "$VPN_IF" | awk '/inet /{for(i=1;i<=NF;i++) if($i=="-->") print $(i+1)}')

sudo -n route -n delete -host "$IP" 2>/dev/null || true
sudo -n route -n add -host "$IP" "$VPN_GW"
```

Result:

```text
sudo: a password is required
```

Because route changes require administrator privileges on macOS, I used the macOS administrator prompt next.

## 5. Added a host route through `fitness`

```sh
set -a
. ./.env
set +a

VPN_IF=ppp0
VPN_GW=$(ifconfig "$VPN_IF" | awk '/inet /{for(i=1;i<=NF;i++) if($i=="-->") print $(i+1)}')

/usr/bin/osascript -e "do shell script \"/sbin/route -n delete -host $IP >/dev/null 2>&1 || true; /sbin/route -n add -host $IP $VPN_GW\" with administrator privileges"
```

Result:

```text
add host 192.168.2.36: gateway 192.168.101.254
```

## 6. Verified the new route

```sh
route -n get "$IP" | egrep 'route to|destination|gateway|interface|ifscope'
```

Result:

```text
route to: 192.168.2.36
destination: 192.168.2.36
gateway: 192.168.101.254
interface: ppp0
```

## 7. Checked SSH port availability

```sh
set -a
. ./.env
set +a

nc -vz -G 5 "$IP" 22
```

Result:

```text
Connection to 192.168.2.36 port 22 [tcp/ssh] succeeded!
```

## 8. Verified SSH login with credentials from `.env`

Used `/usr/bin/expect` so the password from `.env` was not typed into the command line or stored in this file.

```sh
set -a
. ./.env
set +a
export IP LOGIN PASS

/usr/bin/expect <<'EOF'
set timeout 20
set ip $env(IP)
set login $env(LOGIN)
set pass $env(PASS)

spawn ssh \
  -o ConnectTimeout=10 \
  -o BatchMode=no \
  -o PubkeyAuthentication=no \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile=/tmp/1c_preprocess_known_hosts \
  -- $login@$ip \
  "printf 'SSH_CONNECTED:%s:%s\\n' \$(hostname) \$(whoami)"

expect {
  -re "(?i)are you sure you want to continue connecting" {
    send -- "yes\r"
    exp_continue
  }
  -re "(?i)password:" {
    send -- "$pass\r"
    exp_continue
  }
  -re "(?i)permission denied" {
    exit 13
  }
  -re "(?i)connection timed out|no route to host|connection refused" {
    exit 14
  }
  eof {
    catch wait result
    exit [lindex $result 3]
  }
  timeout {
    exit 124
  }
}
EOF
```

Successful result:

```text
SSH_CONNECTED:u26:linuxadmin
```

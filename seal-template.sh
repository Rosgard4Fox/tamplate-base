#!/usr/bin/env bash
# Очистка ВМ перед превращением в шаблон. Запуск: sudo bash seal-template.sh
# После очистки ВМ выключается. Запускать последним шагом, после setup.sh.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root: sudo bash $0" >&2
  exit 1
fi

# Без этой службы клоны останутся без ключей хоста и SSH не поднимется
if ! systemctl is-enabled --quiet ssh-hostkeys.service; then
  echo "ssh-hostkeys.service не включена — сначала выполните setup.sh" >&2
  exit 1
fi

if grep -rqs macaddress /etc/netplan/; then
  echo "ВНИМАНИЕ: в /etc/netplan есть привязка к MAC-адресу, на клонах сеть может не подняться" >&2
fi

read -r -p "Очистить ВМ и выключить её? [y/N] " answer
[[ $answer == [yY] ]] || exit 0

systemctl stop fail2ban rsyslog unattended-upgrades 2>/dev/null || true

apt -y autoremove --purge
apt clean
rm -rf /var/lib/apt/lists/*

# Идентификаторы, которые не должны совпадать у клонов
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_*
rm -f /var/lib/systemd/random-seed
rm -rf /var/lib/systemd/netif/leases/* /var/lib/dhcp/*

rm -f /var/lib/fail2ban/fail2ban.sqlite3
rm -rf /tmp/* /var/tmp/*

# Логи
find /var/log -path /var/log/journal -prune -o -type f \( -name '*.gz' -o -name '*.[0-9]' -o -name '*.old' \) -exec rm -f {} +
find /var/log -path /var/log/journal -prune -o -type f -exec truncate -s 0 {} +
rm -rf /var/log/journal/*

# История команд и следы редакторов у root и всех пользователей
for home in /root /home/*; do
  rm -f "$home"/.bash_history "$home"/.lesshst "$home"/.viminfo "$home"/.wget-hsts
  rm -f "$home"/setup.sh "$home"/keys.sh
done

sync
echo "Готово, выключение."
systemctl poweroff

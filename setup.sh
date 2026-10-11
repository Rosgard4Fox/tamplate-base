#!/usr/bin/env bash
# Базовая настройка Ubuntu 24.04 (шаблон ВМ). Запуск: sudo bash setup.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root: sudo bash $0" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

apt update
apt -y full-upgrade
apt -y install openssh-server chrony locales language-pack-ru unattended-upgrades needrestart ufw fail2ban auditd audispd-plugins apparmor-utils rsyslog lynis sysstat atop iotop htop curl wget tar mc xfsprogs bind9-dnsutils lsof bash-completion vim qemu-guest-agent

locale-gen ru_RU.UTF-8 en_US.UTF-8
update-locale LANG=ru_RU.UTF-8
timedatectl set-timezone Europe/Moscow
systemctl enable --now chrony ssh
systemctl start qemu-guest-agent || true

systemctl disable --now systemd-networkd-wait-online.service || true
systemctl mask systemd-networkd-wait-online.service

ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw --force enable

cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
backend = systemd
EOF
systemctl enable fail2ban
systemctl restart fail2ban

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
cat > /etc/apt/apt.conf.d/52unattended-local <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
mkdir -p /etc/needrestart/conf.d
echo "\$nrconf{restart} = 'a';" > /etc/needrestart/conf.d/90-auto.conf

cat > /etc/audit/rules.d/50-base.rules <<'EOF'
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers
-w /etc/ssh/sshd_config.d/ -p wa -k sshd
-w /etc/ufw/ -p wa -k firewall
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=unset -k root_cmds
EOF
augenrules --load
systemctl enable --now auditd

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/10-persistent.conf <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=1G
EOF
systemctl restart systemd-journald

cat > /etc/sysctl.d/90-base.conf <<'EOF'
vm.swappiness = 10
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.log_martians = 1
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF
sysctl --system

cat > /etc/security/limits.d/90-nofile.conf <<'EOF'
*    soft nofile 65536
*    hard nofile 65536
EOF

sed -i 's/^ENABLED=.*/ENABLED="true"/' /etc/default/sysstat
systemctl enable --now sysstat

systemctl disable --now snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
apt -y purge snapd
apt-mark hold snapd
apt -y autoremove --purge

echo
echo "=== Проверка ==="
systemctl is-active ssh chrony ufw fail2ban auditd || true
ufw status verbose
chronyc tracking || true
echo
echo "Готово. Перезагрузите систему: sudo reboot"

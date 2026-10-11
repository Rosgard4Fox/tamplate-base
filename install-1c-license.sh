#!/usr/bin/env bash
# Установка сервера 1С:Предприятия 8.3 под роль сервера лицензирования в кластере.
# Запуск: sudo bash install-1c-license.sh <ссылка или путь к дистрибутиву> [подсеть кластера]
#   дистрибутив — server64_8_3_27_XXXX.zip / .tar.gz или setup-full-8.3.27.XXXX-x86_64.run
#   подсеть     — откуда открыть порты 1С, например 192.168.250.0/24 (по умолчанию отовсюду)
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root: sudo bash $0 <ссылка или путь> [подсеть]" >&2
  exit 1
fi
if [[ $# -lt 1 ]]; then
  echo "Укажите ссылку или путь к дистрибутиву: sudo bash $0 <ссылка или путь> [подсеть]" >&2
  exit 1
fi

SRC=$1
ALLOW_FROM=${2:-any}

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

apt update
apt -y install unzip unixodbc libgsf-1-114 fontconfig libfreetype6 libkrb5-3 libgssapi-krb5-2

WORK=$(mktemp -d /var/tmp/1c-install.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# Публичная ссылка Яндекс Диска ведёт на страницу; прямую ссылку выдаёт его API
if [[ $SRC =~ ^https?://(disk\.yandex\.[a-z]+|yadi\.sk)/ ]]; then
  SRC=$(curl -fsSG --data-urlencode "public_key=$SRC" https://cloud-api.yandex.net/v1/disk/public/resources/download \
    | grep -o '"href":"[^"]*"' | cut -d'"' -f4 | sed 's/\\u0026/\&/g')
  if [[ -z $SRC ]]; then
    echo "Яндекс Диск не выдал прямую ссылку — проверьте, что доступ по ссылке открыт" >&2
    exit 1
  fi
fi

if [[ $SRC == http://* || $SRC == https://* ]]; then
  curl -fL --retry 3 -o "$WORK/dist" "$SRC"
else
  cp "$SRC" "$WORK/dist"
fi
echo "SHA256 дистрибутива: $(sha256sum "$WORK/dist" | cut -d' ' -f1)"

# Формат определяем по сигнатуре: файлообменники часто отдают HTML-страницу вместо файла
magic=$(head -c 4 "$WORK/dist" | od -An -tx1 | tr -d ' \n')
case $magic in
  504b0304) unzip -q "$WORK/dist" -d "$WORK/unpacked" ;;
  1f8b*)    mkdir "$WORK/unpacked" && tar -xzf "$WORK/dist" -C "$WORK/unpacked" ;;
  7f454c46|2321*) mkdir "$WORK/unpacked" && mv "$WORK/dist" "$WORK/unpacked/setup-full.run" ;;
  *)
    echo "Это не zip, не tar.gz и не .run — похоже, ссылка не прямая (скачалась веб-страница)" >&2
    exit 1
    ;;
esac

RUN=$(find "$WORK/unpacked" -name 'setup-full*.run' | head -n 1)
if [[ -z $RUN ]]; then
  echo "В дистрибутиве нет setup-full-*.run" >&2
  exit 1
fi

chmod +x "$RUN"
"$RUN" --mode unattended --enable-components server,server_admin

# Версию берём из каталога установки: по ссылке файлообменника имя файла может быть любым
VER=$(ls -1 /opt/1cv8/x86_64 2>/dev/null | sort -V | tail -n 1)
if [[ -z $VER ]]; then
  echo "Каталог /opt/1cv8/x86_64 пуст — установка не завершилась" >&2
  exit 1
fi
echo "Версия платформы: $VER"

UNIT=/opt/1cv8/x86_64/$VER/srv1cv8-$VER@.service
if [[ ! -f $UNIT ]]; then
  echo "Не найден $UNIT — установка не завершилась" >&2
  exit 1
fi
systemctl link "$UNIT"
systemctl enable --now "srv1cv8-$VER@default"

# ragent 1540, rmngr 1541, рабочие процессы 1560-1591
if [[ $ALLOW_FROM == any ]]; then
  ufw allow 1540:1541/tcp
  ufw allow 1560:1591/tcp
else
  ufw allow from "$ALLOW_FROM" to any port 1540:1541 proto tcp
  ufw allow from "$ALLOW_FROM" to any port 1560:1591 proto tcp
fi

echo
echo "=== Проверка ==="
sleep 5
systemctl is-active "srv1cv8-$VER@default" || true
ss -tlnp | grep -E ':(154[01]|15[6-9][0-9])\b' || echo "Порты 1С не слушаются" >&2
ufw status

# Центральный сервер кластера обращается к этому по имени
if getent hosts "$(hostname)" | grep -q '^127\.'; then
  echo
  echo "ВНИМАНИЕ: имя $(hostname) разрешается в 127.x.x.x." >&2
  echo "Пропишите в /etc/hosts реальный IP этого сервера, иначе кластер его не подключит." >&2
fi

echo
echo "Готово. Сервер 1С $VER установлен, каталог лицензий: /var/1C/licenses"

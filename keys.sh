#!/usr/bin/env bash
# Добавляет ключи из репозитория в ~/.ssh/authorized_keys текущего пользователя. Запуск: bash keys.sh
set -euo pipefail

URL=https://raw.githubusercontent.com/Rosgard4Fox/tamplate-base/main/authorized_keys
AK=~/.ssh/authorized_keys

mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch "$AK"
curl -fsSL "$URL" | while read -r line; do
  [[ -z $line ]] && continue
  grep -qxF "$line" "$AK" || echo "$line" >> "$AK"
done
chmod 600 "$AK"
ssh-keygen -lf "$AK"

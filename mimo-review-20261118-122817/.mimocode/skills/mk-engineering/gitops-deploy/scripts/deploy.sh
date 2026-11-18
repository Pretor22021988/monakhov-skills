#!/usr/bin/env bash
# Pull-деплой одной машины: состояние = тег (или ветка) в git.
# Использование:
#   deploy.sh <каталог-репозитория> <тег|ветка> ["команда-проверки"] ["команда-перезапуска"]
# Пример (Windows, Git Bash):
#   deploy.sh ~/tbot v5.6 "python -m py_compile tbot_fundamental.py" "./restart.sh"
# Коды выхода: 2 — дрейф (ручные правки), 3 — проверка не прошла, сделан откат.
set -euo pipefail
repo="${1:?каталог репозитория}"; ref="${2:?тег или ветка}"
check="${3:-}"; restart="${4:-}"
log="${DEPLOY_LOG:-$HOME/.deploy-log}"
cd "$repo"

# 1. дрейф: машину не правят руками
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "ДРЕЙФ: в рабочей копии ручные правки — деплой остановлен:"
  git status --short --untracked-files=no
  exit 2
fi

prev=$(git rev-parse HEAD)
git fetch --tags --quiet origin
git checkout --quiet "$ref"
if [ "$(git rev-parse --abbrev-ref HEAD)" != "HEAD" ]; then
  git pull --ff-only --quiet            # ветка — подтянуть до origin
fi
now=$(git rev-parse HEAD)
echo "версия: ${prev:0:7} → ${now:0:7} ($ref)"

# 2. проверка до перезапуска; провал — откат
if [ -n "$check" ] && ! bash -c "$check"; then
  echo "ПРОВЕРКА НЕ ПРОШЛА — откат на ${prev:0:7}"
  git checkout --quiet "$prev"
  echo "$(date '+%Y-%m-%dT%H:%M:%S') ОТКАТ ${now:0:7}→${prev:0:7} ($ref)" >> "$log"
  exit 3
fi

# 3. перезапуск и журнал
if [ -n "$restart" ]; then bash -c "$restart"; fi
echo "$(date '+%Y-%m-%dT%H:%M:%S') ${prev:0:7}→${now:0:7} ($ref)" >> "$log"
echo "готово; журнал: $log"

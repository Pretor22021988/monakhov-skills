#!/usr/bin/env bash
# Библиотека скиллов monakhov-skills: один репозиторий -> все аккаунты Claude и Claude Code.
#
#   bash skills-library.sh init      развернуть библиотеку из ~/Downloads/monakhov-skills.zip в ~/repos/monakhov-skills
#   bash skills-library.sh import    добрать в библиотеку скиллы, которые есть только на диске (~/.claude*/skills, ~/repos/claude-skills/skills)
#   bash skills-library.sh check     проверить структуру, имена, секреты и сам маркетплейс
#   bash skills-library.sh publish   закоммитить и отправить в приватный GitHub-репозиторий
#   bash skills-library.sh zips      собрать dist/<плагин>.zip для ручной загрузки (Customize -> Plugins -> Add -> Upload plugin)
#   bash skills-library.sh park      убрать из ~/.claude*/skills дубли того, что уже есть в библиотеке (перенос, не удаление)
#   bash skills-library.sh cc        поставить маркетплейс в Claude Code напрямую (если синхронизация с аккаунтом не используется)
#   bash skills-library.sh status    что в библиотеке, что ещё не импортировано, состояние git
#   bash skills-library.sh mcp-import  добрать в mk-connectors удалённые коннекторы из Claude Code этой машины (без ключей)
#
# Коннекторы: в плагине лежат только адреса. Вход (OAuth) делается в каждом аккаунте отдельно.
# Переменные: LIB (корень библиотеки), GH_OWNER, GH_REPO, SRC_ZIP.
# Ничего не удаляет: дубли переносятся в ~/.claude*/skills-parked-ГГГГММДД.

set -euo pipefail

LIB="${LIB:-$HOME/repos/monakhov-skills}"
GH_OWNER="${GH_OWNER:-Pretor22021988}"
GH_REPO="${GH_REPO:-monakhov-skills}"
SRC_ZIP="${SRC_ZIP:-$HOME/Downloads/monakhov-skills.zip}"
MP_NAME="monakhov-skills"
LOCAL_PLUGIN="mk-local"
TODAY="$(date +%Y%m%d)"
# Признаки токенов и ключей: такие файлы в библиотеку не попадают
SECRET_RE='(^|[^A-Za-z0-9])(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|xox[bap]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|vk1\.a\.[A-Za-z0-9_-]{20,})|-----BEGIN [A-Z ]*PRIVATE KEY'

# Встроенные скиллы Anthropic есть в каждом аккаунте — в библиотеку их не берём.
BUILTIN=" docx pdf pptx xlsx skill-creator docs deep-research morning import-memory google-workspace built-in-browser chrome-browser computer-use file-reading pdf-reading frontend-design product-self-knowledge "

die() { echo "ОШИБКА: $*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

find_python() {
  local c
  for c in python3 python py; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)' >/dev/null 2>&1; then
      echo "$c"; return 0
    fi
  done
  return 1
}
PY="$(find_python)" || die "нужен Python 3.8+ (python.org, галочка Add Python to PATH)"

# Папки со скиллами на этой машине: основной конфиг и конфиги других аккаунтов (CLAUDE_CONFIG_DIR=~/.claude-2 ...)
skill_roots() {
  local d
  for d in "$HOME/.claude/skills" "$HOME"/.claude-*/skills "$HOME/repos/claude-skills/skills"; do
    [ -d "$d" ] && echo "$d"
  done
  return 0
}

lib_skill_names() {
  [ -d "$LIB/plugins" ] || return 0
  find "$LIB/plugins" -mindepth 4 -maxdepth 4 -name SKILL.md -path '*/skills/*' | sed 's#/SKILL.md$##; s#.*/##' | sort -u
}

cmd_init() {
  if [ -f "$LIB/.claude-plugin/marketplace.json" ]; then
    [ -f "$SRC_ZIP" ] || { say "Библиотека уже есть: $LIB"; return 0; }
    say "Библиотека уже есть — добавляю из архива только то, чего в ней нет (ваши правки не трогаю):"
    "$PY" - "$SRC_ZIP" "$LIB" <<'PYEOF'
import json, os, shutil, sys, tempfile, zipfile
src, lib = sys.argv[1], sys.argv[2]
with tempfile.TemporaryDirectory() as t:
    z = zipfile.ZipFile(src)
    for n in z.namelist():
        if n.startswith('/') or '..' in n.split('/'): sys.exit('небезопасный путь в архиве: ' + n)
    z.extractall(t)
    new = os.path.join(t, 'monakhov-skills')
    for p in sorted(os.listdir(os.path.join(new, 'plugins'))):
        if not os.path.exists(os.path.join(lib, 'plugins', p)):
            shutil.copytree(os.path.join(new, 'plugins', p), os.path.join(lib, 'plugins', p)); print('  + плагин', p)
    mp_old = os.path.join(lib, '.claude-plugin', 'marketplace.json')
    m_old = json.load(open(mp_old, encoding='utf-8')); m_new = json.load(open(os.path.join(new, '.claude-plugin', 'marketplace.json'), encoding='utf-8'))
    names = {e['name'] for e in m_old['plugins']}
    for e in m_new['plugins']:
        if e['name'] not in names: m_old['plugins'].append(e); print('  + запись маркетплейса', e['name'])
    json.dump(m_old, open(mp_old, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    for f in ('tools/skills-library.sh', 'README.md'):
        shutil.copy2(os.path.join(new, f), os.path.join(lib, f)); print('  ~ обновлён', f)
PYEOF
    return 0
  fi
  [ -f "$SRC_ZIP" ] || die "нет архива $SRC_ZIP — скачайте monakhov-skills.zip в Загрузки"
  mkdir -p "$(dirname "$LIB")"
  "$PY" - "$SRC_ZIP" "$(dirname "$LIB")" <<'PYEOF'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
for n in z.namelist():
    if n.startswith('/') or '..' in n.split('/'):
        sys.exit('небезопасный путь в архиве: ' + n)
z.extractall(sys.argv[2])
PYEOF
  [ -f "$LIB/.claude-plugin/marketplace.json" ] || die "после распаковки нет $LIB/.claude-plugin/marketplace.json"
  say "Распаковано в $LIB"
  cmd_status
}

cmd_import() {
  [ -d "$LIB/plugins" ] || die "нет библиотеки, сначала: bash skills-library.sh init"
  local have; have=" $(lib_skill_names | tr '\n' ' ') "
  local dest="$LIB/plugins/$LOCAL_PLUGIN"
  local added=0 skipped=0 root d n
  while IFS= read -r root; do
    for d in "$root"/*/; do
      [ -d "$d" ] || continue
      n="$(basename "$d")"
      case "$n" in synced|skills-parked-*|.*) continue;; esac
      [ -f "$d/SKILL.md" ] || { [ -f "$d/skill.md" ] && say "  ?  $n: файл skill.md в нижнем регистре — переименуйте в SKILL.md"; continue; }
      case "$BUILTIN" in *" $n "*) continue;; esac
      case "$have" in *" $n "*) continue;; esac
      if ! "$PY" - "$d/SKILL.md" "$n" <<'PYEOF'
import re, sys
t = open(sys.argv[1], encoding='utf-8', errors='replace').read()
m = re.match(r'^﻿?---\s*\n(.*?)\n---', t, re.S)
if not m: sys.exit('нет фронтматтера')
nm = re.search(r'^name:\s*["\']?([^"\'\n]+)', m.group(1), re.M)
if not nm or nm.group(1).strip() != sys.argv[2]: sys.exit('name во фронтматтере не совпадает с именем папки')
if not re.search(r'^description:', m.group(1), re.M): sys.exit('нет description')
PYEOF
      then say "  ✗  $n: пропущен (см. причину выше)"; skipped=$((skipped+1)); continue; fi
      if grep -rIlqE "$SECRET_RE" "$d" 2>/dev/null; then
        say "  ✗  $n: похоже на токен или ключ внутри — пропущен, проверьте вручную"; skipped=$((skipped+1)); continue
      fi
      mkdir -p "$dest/skills"
      "$PY" -c 'import shutil,sys; shutil.copytree(sys.argv[1], sys.argv[2], ignore=shutil.ignore_patterns("__pycache__","*.pyc",".git","node_modules",".DS_Store","*.bak-*"))' "$d" "$dest/skills/$n"
      find "$dest/skills/$n" -type f \( -name '*.md' -o -name '*.py' -o -name '*.json' -o -name '*.html' -o -name '*.js' -o -name '*.sh' -o -name '*.txt' -o -name '*.yaml' -o -name '*.yml' \) -exec sed -i 's/\r$//' {} +
      if grep -rIlqE 'exec\(open\(|os\.system\(|curl [^|]*\| *(ba)?sh' "$dest/skills/$n" 2>/dev/null; then
        say "  !  $n: импортирован, но содержит exec(open(...)/os.system/curl|sh — прочитайте перед загрузкой в веб"
      fi
      have="$have$n "; added=$((added+1)); say "  +  $n  (из $root)"
    done
  done < <(skill_roots)
  if [ "$added" -gt 0 ]; then
    mkdir -p "$dest/.claude-plugin"
    [ -f "$dest/.claude-plugin/plugin.json" ] || cat > "$dest/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "mk-local",
  "description": "Скиллы, которые жили только на диске в Claude Code: часть из них вызывает локальные программы или сеть и в веб-чате может не работать",
  "author": { "name": "Alexander Monakhov" }
}
JSON
    "$PY" - "$LIB/.claude-plugin/marketplace.json" <<'PYEOF'
import json, sys
p = sys.argv[1]; m = json.load(open(p, encoding='utf-8'))
if not any(e['name'] == 'mk-local' for e in m['plugins']):
    m['plugins'].append({"name": "mk-local", "source": "./plugins/mk-local",
                         "description": "Скиллы, которые жили только на диске в Claude Code (часть работает только там)"})
    json.dump(m, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
PYEOF
  fi
  say "Импортировано: $added, пропущено: $skipped. Дальше: bash skills-library.sh check"
}

cmd_check() {
  [ -d "$LIB/plugins" ] || die "нет библиотеки $LIB"
  local fail=0
  "$PY" - "$LIB" <<'PYEOF' || fail=1
import json, os, re, sys, collections
lib = sys.argv[1]
m = json.load(open(os.path.join(lib, '.claude-plugin', 'marketplace.json'), encoding='utf-8'))
names = collections.Counter(); bad = 0; total = 0
for e in m['plugins']:
    pd = os.path.join(lib, e['source'])
    pj = os.path.join(pd, '.claude-plugin', 'plugin.json')
    if not os.path.isfile(pj): print('  ✗ нет plugin.json:', e['name']); bad += 1; continue
    if json.load(open(pj, encoding='utf-8')).get('name') != e['name']:
        print('  ✗ имя в plugin.json не совпадает с записью маркетплейса:', e['name']); bad += 1
    sk = os.path.join(pd, 'skills'); cnt = 0
    for s in sorted(os.listdir(sk)) if os.path.isdir(sk) else []:
        f = os.path.join(sk, s, 'SKILL.md')
        if not os.path.isfile(f): print('  ✗ нет SKILL.md:', e['name'] + '/' + s); bad += 1; continue
        t = open(f, encoding='utf-8', errors='replace').read()
        fm = re.match(r'^﻿?---\s*\n(.*?)\n---', t, re.S)
        nm = re.search(r'^name:\s*["\']?([^"\'\n]+)', fm.group(1), re.M) if fm else None
        if not nm or nm.group(1).strip() != s: print('  ✗ name во фронтматтере != папке:', e['name'] + '/' + s); bad += 1
        names[s] += 1; cnt += 1
    total += cnt
    print(f"  ✓ {e['name']:16} скиллов: {cnt}")
for s, c in names.items():
    if c > 1: print('  ✗ скилл в нескольких плагинах:', s); bad += 1
print(f"Всего скиллов: {total}")
sys.exit(1 if bad else 0)
PYEOF
  if grep -rIlE "$SECRET_RE" "$LIB/plugins" 2>/dev/null; then
    say "  ✗ в файлах выше похоже на токены — уберите до publish"; fail=1
  else
    say "  ✓ токенов и ключей не найдено"
  fi
  if [ -d "$LIB/plugins" ] && find "$LIB/plugins" -mindepth 2 -maxdepth 2 -type d -name bin | grep -q .; then
    say "  ✗ в плагине есть папка bin/ верхнего уровня — переименуйте в scripts/"; fail=1
  fi
  "$PY" - "$LIB" <<'PYEOF' || fail=1
import glob, json, os, re, sys
bad = 0; n = 0
tok = re.compile(r'/[A-Za-z0-9_-]{24,}(/|$)|[?&](api[_-]?key|key|token|access_token|secret)=', re.I)
for f in glob.glob(os.path.join(sys.argv[1], 'plugins', '*', '.mcp.json')):
    for name, c in json.load(open(f, encoding='utf-8')).get('mcpServers', {}).items():
        n += 1
        if c.get('headers') or c.get('env'):
            print(f'  ✗ коннектор {name}: в .mcp.json заголовки или env — ключи туда класть нельзя'); bad += 1
        if tok.search(c.get('url', '')):
            print(f'  ✗ коннектор {name}: в адресе похоже на ключ — уберите из .mcp.json'); bad += 1
print(f'  ✓ коннекторов: {n}, ключей в .mcp.json нет' if not bad else '')
sys.exit(1 if bad else 0)
PYEOF
  if command -v claude >/dev/null 2>&1; then
    claude plugin validate "$LIB" 2>&1 | grep -vE 'No version specified|Found [0-9]+ warning|^[[:space:]]*$' | tail -3
  else
    say "  (claude не найден в PATH — пропускаю claude plugin validate)"
  fi
  [ "$fail" -eq 0 ] && say "Проверка пройдена." || die "проверка не пройдена"
}

cmd_publish() {
  [ -d "$LIB/.claude-plugin" ] || die "нет библиотеки $LIB"
  command -v git >/dev/null 2>&1 || die "нужен git"
  cmd_check
  cd "$LIB"
  [ -d .git ] || { git init -q -b main 2>/dev/null || { git init -q && git checkout -q -b main; }; }
  git config user.email >/dev/null 2>&1 || git config user.email "$GH_OWNER@users.noreply.github.com"
  git config user.name  >/dev/null 2>&1 || git config user.name "$GH_OWNER"
  git add -A
  if git diff --cached --quiet; then say "Нечего коммитить."; else git commit -qm "skills: обновление $(date +%Y-%m-%d)" && say "Коммит создан."; fi
  if ! git remote get-url origin >/dev/null 2>&1; then
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
      gh repo create "$GH_OWNER/$GH_REPO" --private --source . --remote origin --push
      say "Создан приватный репозиторий https://github.com/$GH_OWNER/$GH_REPO"
      return 0
    fi
    say "gh не установлен или не авторизован. Один раз вручную:"
    say "  1) https://github.com/new -> Repository name: $GH_REPO -> Private -> Create (без README)"
    say "  2) bash skills-library.sh publish   ещё раз — remote уже добавлен, будет push"
    git remote add origin "https://github.com/$GH_OWNER/$GH_REPO.git"
    return 0
  fi
  git push -u origin main && say "Отправлено в $(git remote get-url origin). Аккаунты с «Sync automatically» подтянут сами."
}

cmd_zips() {
  [ -d "$LIB/plugins" ] || die "нет библиотеки $LIB"
  mkdir -p "$LIB/dist"
  "$PY" - "$LIB" <<'PYEOF'
import os, sys, zipfile
lib = sys.argv[1]
for p in sorted(os.listdir(os.path.join(lib, 'plugins'))):
    src = os.path.join(lib, 'plugins', p)
    out = os.path.join(lib, 'dist', p + '.zip')
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for r, ds, fs in os.walk(src):
            ds[:] = [d for d in ds if d not in ('__pycache__', '.git', 'node_modules')]
            for f in fs:
                if f.endswith('.pyc'): continue
                full = os.path.join(r, f)
                z.write(full, os.path.join(p, os.path.relpath(full, src)))
    print(f"  {p}.zip  {os.path.getsize(out)//1024} КБ")
print('Папка:', os.path.join(lib, 'dist'))
PYEOF
}

cmd_park() {
  [ -d "$LIB/plugins" ] || die "нет библиотеки $LIB"
  if [ "${FORCE:-0}" != "1" ]; then
    command -v claude >/dev/null 2>&1 || die "claude не найден — без него не проверить, что плагины уже стоят (FORCE=1 чтобы перенести всё равно)"
    claude plugin list 2>/dev/null | grep -q 'mk-legal' || die "в Claude Code ещё нет плагина mk-legal: сначала поставьте библиотеку в аккаунт (или bash skills-library.sh cc), перезапустите claude, потом park"
  fi
  local have; have=" $(lib_skill_names | tr '\n' ' ') "
  local root n moved=0 dst
  while IFS= read -r root; do
    case "$root" in "$HOME/repos/"*) continue;; esac   # исходники не трогаем
    dst="$(dirname "$root")/skills-parked-$TODAY"
    for d in "$root"/*/; do
      [ -d "$d" ] || continue; n="$(basename "$d")"
      case "$n" in synced|skills-parked-*) continue;; esac
      case "$have" in *" $n "*) ;; *) continue;; esac
      mkdir -p "$dst"
      if [ -e "$dst/$n" ]; then say "  =  $n уже в $dst — оставил на месте"; continue; fi
      mv "$d" "$dst/$n" && moved=$((moved+1)) && say "  →  $n  ->  $dst/"
    done
  done < <(skill_roots)
  say "Перенесено дублей: $moved. Вернуть: mv <папка>/skills-parked-$TODAY/* <папка>/skills/"
}

cmd_cc() {
  command -v claude >/dev/null 2>&1 || die "claude не найден в PATH"
  local src cfg p plugins
  if [ -d "$LIB/.git" ] && git -C "$LIB" remote get-url origin >/dev/null 2>&1; then src="$GH_OWNER/$GH_REPO"; else src="$LIB"; fi
  plugins="$("$PY" -c 'import json,sys; print(" ".join(e["name"] for e in json.load(open(sys.argv[1],encoding="utf-8"))["plugins"]))' "$LIB/.claude-plugin/marketplace.json")"
  for cfg in "$HOME/.claude" "$HOME"/.claude-*; do
    [ -d "$cfg" ] || continue
    case "$cfg" in *skills-parked*) continue;; esac
    say "== $cfg"
    CLAUDE_CONFIG_DIR="$cfg" claude plugin marketplace add "$src" 2>&1 | tail -1 || true
    for p in $plugins; do CLAUDE_CONFIG_DIR="$cfg" claude plugin install "$p@$MP_NAME" 2>&1 | tail -1 || true; done
  done
  say "Внутри сессии один раз: /plugin -> Marketplaces -> $MP_NAME -> Enable auto-update; затем /reload-plugins"
}

cmd_status() {
  say "Библиотека: $LIB"
  [ -d "$LIB/plugins" ] || { say "  (не развёрнута — bash skills-library.sh init)"; return 0; }
  local p
  for p in "$LIB"/plugins/*/; do printf '  %-16s %s скиллов\n' "$(basename "$p")" "$(find "$p/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"; done
  local have; have=" $(lib_skill_names | tr '\n' ' ') "; local miss="" root n
  while IFS= read -r root; do
    for d in "$root"/*/; do [ -f "$d/SKILL.md" ] || continue; n="$(basename "$d")"
      case "$BUILTIN" in *" $n "*) continue;; esac
      case "$have" in *" $n "*) ;; *) miss="$miss $n";; esac
    done
  done < <(skill_roots)
  [ -n "$miss" ] && say "Есть на диске, нет в библиотеке:$miss  -> bash skills-library.sh import" || say "Всё, что есть на диске, уже в библиотеке."
  if [ -d "$LIB/.git" ]; then say "git: $(git -C "$LIB" remote get-url origin 2>/dev/null || echo 'remote не задан'); незакоммиченных файлов: $(git -C "$LIB" status --porcelain | wc -l | tr -d ' ')"; fi
}

cmd_mcp_import() {
  local dest="$LIB/plugins/mk-connectors/.mcp.json"
  [ -f "$dest" ] || die "нет $dest — сначала init"
  "$PY" - "$dest" "$HOME" <<'PYEOF'
import glob, json, os, re, sys
dest, home = sys.argv[1], sys.argv[2]
cfg = json.load(open(dest, encoding='utf-8')); srv = cfg.setdefault('mcpServers', {})
have = {c.get('url', '').rstrip('/') for c in srv.values()}
tok = re.compile(r'/[A-Za-z0-9_-]{24,}(/|$)|[?&](api[_-]?key|key|token|access_token|secret)=', re.I)
added = 0
for f in [os.path.join(home, '.claude.json')] + glob.glob(os.path.join(home, '.claude-*', '.claude.json')):
    if not os.path.isfile(f): continue
    try: d = json.load(open(f, encoding='utf-8'))
    except Exception as e: print('  ? не прочитать', f, e); continue
    for name, c in (d.get('mcpServers') or {}).items():
        url = (c.get('url') or '').rstrip('/')
        if c.get('type') not in ('http', 'sse') or not url:
            print(f'  ·  {name}: локальный сервер (команда) — остаётся только в Claude Code'); continue
        if url in have: continue
        if c.get('headers') or tok.search(url):
            print(f'  ✗  {name}: ключ в адресе или заголовке — в библиотеку не беру, подключайте вручную'); continue
        key = name if name not in srv else name + '-2'
        srv[key] = {'type': c['type'], 'url': url}; have.add(url); added += 1
        print(f'  +  {key}: {url}')
json.dump(cfg, open(dest, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print(f'Добавлено коннекторов: {added}. Дальше: bash skills-library.sh check, затем publish')
PYEOF
}

case "${1:-status}" in
  init) cmd_init;; import) cmd_import;; check) cmd_check;; publish) cmd_publish;;
  zips) cmd_zips;; park) cmd_park;; cc) cmd_cc;; status) cmd_status;;
  mcp-import) cmd_mcp_import;;
  *) sed -n '2,16p' "$0"; exit 1;;
esac

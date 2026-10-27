#!/usr/bin/env bash
# Плагин mk-design: сторонние дизайн-скиллы, собранные из исходных репозиториев.
#
#   bash update-mk-design.sh     перекачать источники и пересобрать plugins/mk-design
#   затем: bash skills-library.sh check && bash skills-library.sh publish
#
# Источники и что из них берётся:
#   pbakaus/impeccable                    plugin/skills/impeccable + plugin/agents
#                                         (хуки upstream НЕ берутся: они срабатывали бы на каждой правке файла во всех проектах)
#   Leonxlnx/taste-skill                  skills/taste-skill -> skills/design-taste-frontend (имя папки = name)
#   emilkowalski/skills                   skills/* — все скиллы Эмиля Ковальски
#   nextlevelbuilder/ui-ux-pro-max-skill  .claude/skills/ui-ux-pro-max — только основной скилл
#                                         (design, slides, brand, banner-design, design-system, ui-styling не берутся:
#                                          перехватывают задачи «презентация», «бренд», «дизайн» у Slides/Design и mk-content)
# Правка: в ui-ux-pro-max путь ${CLAUDE_PLUGIN_ROOT}/.claude/skills/ui-ux-pro-max/ -> ${CLAUDE_SKILL_DIR}/
# (upstream рассчитан на свою раскладку плагина; в mk-design и в чате путь другой).
# LICENSE (и NOTICE.md у Impeccable) кладутся в папку каждого скилла.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${LIB:-$(dirname "$here")}"
PLUGIN="mk-design"
P="$LIB/plugins/$PLUGIN"

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
PY="$(find_python)" || die "нужен Python 3.8+"
command -v git >/dev/null 2>&1 || die "нужен git"
[ -f "$LIB/.claude-plugin/marketplace.json" ] || die "нет библиотеки $LIB (задайте LIB=...)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SRC="$TMP/src"; NEW="$TMP/$PLUGIN"
mkdir -p "$SRC" "$NEW/.claude-plugin" "$NEW/skills" "$NEW/agents"

: > "$TMP/upstream.tsv"
fetch() {  # fetch owner/repo dir
  say "  ↓ $1"
  git clone -q --depth 1 "https://github.com/$1.git" "$SRC/$2" || die "не скачался $1"
  printf '%s\t%s\n' "$1" "$(git -C "$SRC/$2" log -1 --format='%h %cs')" >> "$TMP/upstream.tsv"
}
fetch pbakaus/impeccable impeccable
fetch Leonxlnx/taste-skill taste
fetch emilkowalski/skills emil
fetch nextlevelbuilder/ui-ux-pro-max-skill uiux

# 1. Impeccable
cp -R "$SRC/impeccable/plugin/skills/impeccable" "$NEW/skills/impeccable"
cp "$SRC/impeccable/plugin/agents/"*.md "$NEW/agents/"
cp "$SRC/impeccable/LICENSE" "$NEW/skills/impeccable/LICENSE"
[ -f "$SRC/impeccable/NOTICE.md" ] && cp "$SRC/impeccable/NOTICE.md" "$NEW/skills/impeccable/NOTICE.md"
chmod +x "$NEW/skills/impeccable/scripts/impeccable" 2>/dev/null || true

# 2. Taste Skill
cp -R "$SRC/taste/skills/taste-skill" "$NEW/skills/design-taste-frontend"
rm -rf "$NEW/skills/design-taste-frontend/evals"
cp "$SRC/taste/LICENSE" "$NEW/skills/design-taste-frontend/LICENSE"

# 3. Emil Kowalski
for d in "$SRC/emil/skills"/*/; do
  n="$(basename "$d")"
  cp -R "$d" "$NEW/skills/$n"
  cp "$SRC/emil/LICENSE" "$NEW/skills/$n/LICENSE"
done

# 4. UI UX Pro Max
cp -R "$SRC/uiux/.claude/skills/ui-ux-pro-max" "$NEW/skills/ui-ux-pro-max"
rm -rf "$NEW/skills/ui-ux-pro-max/scripts/tests"
cp "$SRC/uiux/LICENSE" "$NEW/skills/ui-ux-pro-max/LICENSE"

find "$NEW" \( -name __pycache__ -o -name node_modules -o -name .DS_Store \) -prune -exec rm -rf {} + 2>/dev/null || true

"$PY" - "$NEW" "$LIB" "$TMP/upstream.tsv" <<'PYEOF'
import json, os, re, sys
new, lib, ups = sys.argv[1], sys.argv[2], sys.argv[3]

# ui-ux-pro-max: путь к скриптам
f = os.path.join(new, 'skills', 'ui-ux-pro-max', 'SKILL.md')
t = open(f, encoding='utf-8').read()
old = '${CLAUDE_PLUGIN_ROOT}/.claude/skills/ui-ux-pro-max/'
n = t.count(old)
t = t.replace(old, '${CLAUDE_SKILL_DIR}/')
note = ('> Paths: `${CLAUDE_SKILL_DIR}` is the folder that contains this SKILL.md; substitute it before '
        'running a command. If `python` is not found, use `python3` (Windows: `py`).\n')
if note not in t:
    t = re.sub(r'^(---\s*\n.*?\n---\s*\n)', lambda m: m.group(1) + '\n' + note, t, count=1, flags=re.S)
open(f, 'w', encoding='utf-8', newline='\n').write(t)
print(f'  ui-ux-pro-max: путей исправлено {n}')
if n == 0 and '${CLAUDE_SKILL_DIR}/scripts/search.py' not in t:
    print('  ! в ui-ux-pro-max не найден путь к search.py — проверьте SKILL.md вручную')

def desc(path):
    t = open(path, encoding='utf-8', errors='replace').read()
    fm = re.match(r'^﻿?---\s*\n(.*?)\n---', t, re.S)
    if not fm: return ''
    lines = fm.group(1).split('\n'); out = []
    for i, l in enumerate(lines):
        m = re.match(r'^description:\s*(.*)$', l)
        if not m: continue
        v = m.group(1).strip()
        if v in ('>', '>-', '|', '|-', ''):
            for c in lines[i+1:]:
                if c[:1] in (' ', '\t'): out.append(c.strip())
                else: break
            v = ' '.join(out)
        return v.strip().strip('"\'')
    return ''

def short(s, n=170):
    s = re.sub(r'\s+', ' ', s).replace('|', '/')
    return s if len(s) <= n else s[:n].rsplit(' ', 1)[0] + '…'

skills = sorted(os.listdir(os.path.join(new, 'skills')))
up = [l.rstrip('\n').split('\t') for l in open(ups, encoding='utf-8') if l.strip()]

pdesc = ('Дизайн интерфейсов: Impeccable (антиштампы ИИ, 24 команды), Taste Skill (арт-дирекшн с проверкой '
         'в браузере), анимации и UI-инженерия Эмиля Ковальски, UI UX Pro Max (палитры, шрифтовые пары, дизайн-система)')
json.dump({'name': 'mk-design', 'description': pdesc, 'author': {'name': 'Alexander Monakhov'}},
          open(os.path.join(new, '.claude-plugin', 'plugin.json'), 'w', encoding='utf-8'),
          ensure_ascii=False, indent=2)

origin = {'impeccable': 'pbakaus/impeccable', 'design-taste-frontend': 'Leonxlnx/taste-skill',
          'ui-ux-pro-max': 'nextlevelbuilder/ui-ux-pro-max-skill'}
rows = '\n'.join(f"| `{s}` | {origin.get(s, 'emilkowalski/skills')} | "
                 f"{short(desc(os.path.join(new, 'skills', s, 'SKILL.md')))} |" for s in skills)
agents = ', '.join(f'`{a[:-3]}`' for a in sorted(os.listdir(os.path.join(new, 'agents'))))
upt = '\n'.join(f'| [{r}](https://github.com/{r}) | `{v}` |' for r, v in up)
readme = f"""# mk-design

{pdesc}.

| Скилл | Источник | Когда применяется |
|---|---|---|
{rows}

Агенты Impeccable (только Claude Code и Cowork): {agents}.

## Что не взято из источников

- Хуки Impeccable (SessionStart, PostToolUse на Edit/Write, Stop): в плагине они бы запускались на каждой правке файла в любом проекте. Команды `/impeccable audit`, `polish`, `critique` и детектор работают и без них.
- Из UI UX Pro Max — только основной скилл. `design`, `slides`, `brand`, `banner-design`, `design-system`, `ui-styling` не взяты: они перехватывают запросы «сделай презентацию / бренд / дизайн» у встроенных Slides и Design и у mk-content, а `design` требует ключей Gemini или MuAPI.

## Что нужно на компьютере

- Impeccable при первом запуске сам скачивает движок с GitHub Releases в `~/.impeccable/bin/` и сверяет его контрольную сумму; Node не нужен.
- Taste Skill: Node 22+ и Chrome, Edge или Chromium — для проверки страницы в браузере на трёх ширинах; без них скилл работает, но без скриншотов.
- UI UX Pro Max: Python 3 (поиск по встроенной базе, сеть не нужна).

## Версии источников

| Репозиторий | Коммит |
|---|---|
{upt}

Установка в Claude Code (2.1.275+): `/plugin install mk-design --marketplace Pretor22021988/monakhov-skills`

Обновить: `bash tools/update-mk-design.sh`, затем `bash tools/skills-library.sh check` и `publish`.
Лицензии лежат в папке каждого скилла (MIT; Impeccable — Apache 2.0 с NOTICE.md).
"""
open(os.path.join(new, 'README.md'), 'w', encoding='utf-8', newline='\n').write(readme)

# запись в маркетплейсе
mp = os.path.join(lib, '.claude-plugin', 'marketplace.json')
m = json.load(open(mp, encoding='utf-8'))
entry = {'name': 'mk-design', 'source': './plugins/mk-design', 'description': pdesc}
for i, e in enumerate(m['plugins']):
    if e['name'] == 'mk-design': m['plugins'][i] = entry; break
else:
    idx = next((i for i, e in enumerate(m['plugins']) if e['name'] == 'mk-connectors'), len(m['plugins']))
    m['plugins'].insert(idx, entry)
open(mp, 'w', encoding='utf-8', newline='\n').write(json.dumps(m, ensure_ascii=False, indent=2) + '\n')

# строка в README библиотеки
rp = os.path.join(lib, 'README.md')
r = open(rp, encoding='utf-8').read()
row = f"| `mk-design` | {len(skills)} | {', '.join(skills)} |"
if re.search(r'^\| `mk-design` \|.*$', r, re.M):
    r = re.sub(r'^\| `mk-design` \|.*$', lambda _: row, r, count=1, flags=re.M)
elif '| `mk-local` |' in r:
    r = r.replace('| `mk-local` |', row + '\n| `mk-local` |', 1)
open(rp, 'w', encoding='utf-8', newline='\n').write(r)
print(f'  скиллов: {len(skills)}, агентов: {len(os.listdir(os.path.join(new, "agents")))}')
PYEOF

# замена папки плагина (старая версия остаётся в истории git)
if [ -d "$P" ]; then mv "$P" "$TMP/old-$PLUGIN"; fi
mv "$NEW" "$P"
say "Готово: $P"
say "Дальше: bash skills-library.sh check && bash skills-library.sh publish"

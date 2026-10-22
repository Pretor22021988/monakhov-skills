# monakhov-skills — библиотека скиллов для всех аккаунтов Claude

Один приватный GitHub-репозиторий, оформленный как маркетплейс плагинов Claude. Каждый аккаунт подключает его один раз; дальше любая правка, отправленная в репозиторий, сама доходит до чата (веб, десктоп, мобильный), Cowork и Claude Code во всех аккаунтах, где включено «Sync automatically».

## Состав

| Плагин | Скиллов | Скиллы |
|---|---|---|
| `mk-legal` | 10 | bevzenko, casuslegal-razbor, casuslegal-sudebny-dokument, contract-review, devils-advocate, general-counsel-advisor, legal-docs-ru, otvety-na-ploshchadkah, praktika-pod-tezisy, proverka-akta |
| `mk-research` | 10 | cyberleninka, exploratory-data-analysis, literature-review, peer-review, ru-sources, scholar-evaluation, scientific-critical-thinking, scientific-writing, shap, statistical-analysis |
| `mk-career` | 9 | application-form-filler, career-changer-translator, cover-letter-generator, interview-prep-generator, job-description-analyzer, resume-ats-optimizer, resume-quantifier, resume-tailor, salary-negotiation-prep |
| `mk-content` | 9 | content-humanizer, diagram-design, linkedin-content-planner, linkedin-hook-extractor, linkedin-hook-generator, linkedin-post-writer, linkedin-profile-optimizer, md-document, roast |
| `mk-security` | 5 | auditing-mcp-servers-for-tool-poisoning, building-incident-response-playbook, conducting-cyber-risk-assessment-with-nist-800-30, conducting-gdpr-compliance-assessment, detecting-indirect-prompt-injection |
| `mk-engineering` | 4 | gitops-deploy, impact-over-tools, slo-reliability, terraform-as-system |
| `mk-local` | — | появляется после `import`: скиллы, которые жили только на диске в Claude Code |
| `mk-connectors` | — | 11 коннекторов без ключей: amazingcat, courtlistener, consensus, elicit, scite, scholar-gateway, pubmed, clinical-trials, firecrawl, semantica, context7 |

Встроенные скиллы Anthropic (docx, pdf, pptx, xlsx, skill-creator и др.) в библиотеку не входят: они и так есть в каждом аккаунте.

В чате скилл вызывается как `/mk-legal:bevzenko`, но обычно Claude подхватывает его сам по описанию задачи.

## Структура

```
.claude-plugin/marketplace.json      каталог: имя маркетплейса и список плагинов
plugins/<плагин>/.claude-plugin/plugin.json
plugins/<плагин>/skills/<скилл>/SKILL.md   имя папки = name во фронтматтере
tools/skills-library.sh              обслуживание библиотеки
```

Поле `version` в `plugin.json` намеренно не задано: без него обновления идут по коммитам, и каждый push доходит до аккаунтов без ручного повышения версии.

## Обслуживание (Git Bash, из папки tools)

| Команда | Что делает |
|---|---|
| `bash skills-library.sh status` | что в библиотеке и что есть на диске, но ещё не импортировано |
| `bash skills-library.sh import` | добирает скиллы из `~/.claude/skills`, `~/.claude-*/skills`, `~/repos/claude-skills/skills` в плагин `mk-local`; пропускает встроенные, скиллы с несовпадающим `name` и файлы с токенами |
| `bash skills-library.sh check` | структура, имена, дубли, токены, `claude plugin validate` |
| `bash skills-library.sh publish` | коммит и push в приватный репозиторий (при первом запуске создаёт его через `gh`) |
| `bash skills-library.sh zips` | `dist/<плагин>.zip` для ручной загрузки, если GitHub недоступен |
| `bash skills-library.sh park` | переносит из `~/.claude*/skills` в `skills-parked-ГГГГММДД` то, что уже приходит плагинами (ничего не удаляет; работает, только когда плагины уже стоят в Claude Code) |
| `bash skills-library.sh cc` | ставит маркетплейс в Claude Code напрямую во все `~/.claude*` (запасной путь, если синхронизация с аккаунтом выключена) |

## Подключение аккаунта (один раз на каждый из четырёх)

1. claude.ai или десктоп → **Customize → Plugins → Add → Add marketplace**.
2. Ввести `Pretor22021988/monakhov-skills`. Репозиторий приватный: на запрос нажать **Connect GitHub**, затем **Install the Claude GitHub App** и дать доступ только к этому репозиторию.
3. В **Discover** установить плагины `mk-*`.
4. У маркетплейса включить **Sync automatically**.
5. **Customize → Skills**: выключить старые одиночные загрузки с теми же именами, иначе каждый скилл будет в двух экземплярах.
6. **Customize → Plugins → mk-connectors → Connectors**: у каждой строки **Add** и **Connect**, вход в сервис в браузере. Уже подключённые по тому же адресу показываются как **Connected**.

## Коннекторы

Плагин переносит адреса коннекторов, но не вход: OAuth привязан к аккаунту, поэтому **Connect** нажимается в каждом аккаунте отдельно — это ограничение платформы, а не библиотеки. Ключи в `.mcp.json` не кладутся никогда: файл получает каждый, кто ставит плагин; `check` это проверяет.

- Добавить коннектор: строка в `plugins/mk-connectors/.mcp.json` (`"имя": {"type": "http", "url": "..."}`), затем `check` и `publish`.
- Забрать в библиотеку всё, что уже подключено в Claude Code на этой машине: `bash skills-library.sh mcp-import` (серверы с ключом в адресе или заголовке и локальные пропускаются).
- Google Drive и другие встроенные коннекторы Anthropic подключаются из каталога **Customize → Connectors**.
- В чате работают только удалённые коннекторы с постоянным адресом; локальные серверы (команда на компьютере) — только в Claude Code и локальном Cowork.

Claude Code получает эти плагины сам при следующем запуске под тем же аккаунтом (`/reload-plugins` — без перезапуска). После этого — `bash skills-library.sh park`.

## Добавить или изменить скилл

1. Положить папку в `plugins/<подходящий плагин>/skills/<имя>/`, внутри `SKILL.md` с `name: <имя>` и `description`, где сказано, *когда* применять.
2. `bash skills-library.sh check`
3. `bash skills-library.sh publish`

## Ограничения

- Плагины есть на Pro, Max, Team и Enterprise; на Free — нет.
- В чате работают скиллы, команды и коннекторы; агенты, хуки и локальные MCP — только в Cowork и Claude Code.
- Скиллы, которым нужны локальные программы или сеть (часть `mk-local`), работают только в Claude Code.
- Коннекторы (OAuth) в каждом аккаунте подключаются отдельно — библиотека их не переносит.
- Плагин, загруженный zip-архивом, сам не обновляется; обновляется только подключённый маркетплейс.
- Лицензии сторонних скиллов лежат в их папках (`LICENSE`, поле `license`). Репозиторий держать приватным.

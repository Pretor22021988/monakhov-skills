# mk-design

Дизайн интерфейсов: Impeccable (антиштампы ИИ, 24 команды), Taste Skill (арт-дирекшн с проверкой в браузере), анимации и UI-инженерия Эмиля Ковальски, UI UX Pro Max (палитры, шрифтовые пары, дизайн-система).

| Скилл | Источник | Когда применяется |
|---|---|---|
| `animate` | emilkowalski/skills | Build an animation from scratch, making the decisions in the order that determines whether it feels right — should it animate at all, what purpose, which tool, which… |
| `animate-expo` | emilkowalski/skills | Build animations in React Native and Expo, making the decisions in the order that determines whether they feel right — should it animate, which thread it runs on, which… |
| `animation-performance` | emilkowalski/skills | Keep web animations inside the frame budget — animate composite-only properties, keep motion off the main thread when the page is busy, and find the cause when an… |
| `animation-vocabulary` | emilkowalski/skills | Reverse-lookup glossary that turns a vague description of a web animation or motion effect into its exact term ("the bouncy thing when a popover opens" → Pop in; "the… |
| `apple-design` | emilkowalski/skills | Apple's approach to interface design and fluid, physical motion, translated for the web. Use when building or reviewing gesture-driven UI, spring animations,… |
| `ask-sonner` | emilkowalski/skills | Guide to Sonner, the React toast library — install and wire up the Toaster, pick the right toast() call, promise and loading toasts, updating, dismissing and persisting… |
| `break-ui` | emilkowalski/skills | Try to break a piece of UI by feeding it worst-case data — long names, unbreakable emails, one-letter names, missing fields, huge counts, zero items, long labels,… |
| `design-taste-frontend` | Leonxlnx/taste-skill | tasteskill v2, the anti-slop frontend skill. Art direction for websites, distilled from a study of 247 curated gallery sites (One Page Love, Awwwards Sites of the Day).… |
| `emil-design-eng` | emilkowalski/skills | This skill encodes Emil Kowalski's philosophy on UI polish, component design, animation decisions, and the invisible details that make software feel great. |
| `find-animation-opportunities` | emilkowalski/skills | Search a codebase or UI for places that don't animate but should, and reject everything that shouldn't. Read-only; it proposes motion with exact values, it does not… |
| `impeccable` | pbakaus/impeccable | Use when the user wants to design, redesign, shape, critique, audit, polish, simplify, harden, animate, or otherwise improve a frontend interface: websites, landing… |
| `improve-animations` | emilkowalski/skills | Survey a codebase's animation and motion code as a senior motion advisor, then produce a prioritized audit and self-contained implementation plans for other agents (or… |
| `mobile-native` | emilkowalski/skills | Make a web app feel native on a phone — the small CSS and meta-tag fixes that separate "a website in a browser" from something that feels installed. Covers sticky hover… |
| `pick-ui-library` | emilkowalski/skills | Pick the right library for a given frontend task from a curated, opinionated list — numbers, OTP inputs, charts, command menus, virtualization, drag and drop, toasts,… |
| `prototype` | emilkowalski/skills | Build multiple genuinely different versions of a UI piece you describe, rendered behind a visual picker so you can flip through them live and promote the one that feels… |
| `review-animations` | emilkowalski/skills | Reviews animation and motion code against a high craft bar derived from Emil Kowalski's design engineering philosophy. Default to flagging; approval is earned. |
| `ui-ux-pro-max` | nextlevelbuilder/ui-ux-pro-max-skill | UI/UX design intelligence for web, mobile, and desktop. This skill should be used when designing, building, reviewing, or fixing interfaces, including pages, components,… |
| `write-swift` | emilkowalski/skills | How to write modern Swift well — modeling with value types, Swift 6 data-race safety and approachable concurrency (@concurrent, main-actor-by-default, actors, task… |

Агенты Impeccable (только Claude Code и Cowork): `impeccable-asset-producer`, `impeccable-documenter`, `impeccable-finish-reviewer`, `impeccable-manual-edit-applier`.

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
| [pbakaus/impeccable](https://github.com/pbakaus/impeccable) | `d34c87e 2026-10-27` |
| [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) | `12af471 2026-10-25` |
| [emilkowalski/skills](https://github.com/emilkowalski/skills) | `2d22863 2026-10-11` |
| [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | `28b3b8d 2026-10-26` |

Установка в Claude Code (2.1.275+): `/plugin install mk-design --marketplace Pretor22021988/monakhov-skills`

Обновить: `bash tools/update-mk-design.sh`, затем `bash tools/skills-library.sh check` и `publish`.
Лицензии лежат в папке каждого скилла (MIT; Impeccable — Apache 2.0 с NOTICE.md).

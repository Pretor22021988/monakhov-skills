#!/usr/bin/env python3
"""
Поиск научных статей в КиберЛенинке (cyberleninka.ru).

Только стандартная библиотека Python 3.8+. Ничего ставить не нужно.

Примеры:
    python3 cyberleninka_search.py "субсидиарная ответственность"
    python3 cyberleninka_search.py "освобождение от долгов" --pages 5
    python3 cyberleninka_search.py "цессия" --format gost
    python3 cyberleninka_search.py "банкротство граждан" --format json > out.json
    python3 cyberleninka_search.py "тест" --html-file saved.html   # разбор сохранённой страницы
    python3 cyberleninka_search.py "цессия" --catalog vak            # только журналы перечня ВАК
    python3 cyberleninka_search.py "цессия" --fulltext 5             # + полные тексты первых пяти

По умолчанию поиск идёт по всему архиву без ограничения по годам.
Фильтр --since применяется только если вы его укажете явно.
"""

import argparse
import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://cyberleninka.ru"
SEARCH_HTML = BASE + "/search"
SEARCH_API = BASE + "/api/search"
UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")

ARTICLE_RE = re.compile(r'href="(/article/n/[^"#?]+)"[^>]*>(.*?)</a>', re.S)
TAG_RE = re.compile(r"<[^>]+>")
YEAR_RE = re.compile(r"\b(1[89]\d{2}|20\d{2})\b")
WS_RE = re.compile(r"\s+")

# Коды перечней в параметре "catalogs" внутреннего API. Взяты из открытого
# парсера Rikanskey/cyberleninka-parser (2021). API недокументирован, поэтому
# при каждом запросе с --catalog скрипт сам проверяет, что фильтр сработал
# (см. check_catalog_filter), и не отдаёт неотфильтрованную выдачу за фильтрованную.
CATALOGS = {"vak": 8, "rsci": 22, "scopus": 2}
CATALOG_NAMES = {"vak": "ВАК", "rsci": "РИНЦ", "scopus": "Scopus"}
LABEL_RE = re.compile(r'class="label\s+(vak|rsci|scopus)\b', re.I)
BODY_RES = [
    re.compile(r'itemprop="articleBody"[^>]*>(.*?)</div>\s*</div>', re.S | re.I),
    re.compile(r'<div[^>]+class="ocr"[^>]*>(.*?)</div>', re.S | re.I),
]


def clean(raw):
    """Снять теги, развернуть сущности, сжать пробелы."""
    raw = re.sub(r"<[^>]*$", " ", raw or "")   # обрезанный на срезе хвост тега
    return WS_RE.sub(" ", html.unescape(TAG_RE.sub(" ", raw))).strip()


def fetch(url, data=None, timeout=25):
    headers = {
        "User-Agent": UA,
        "Accept-Language": "ru-RU,ru;q=0.9",
        "Accept": "text/html,application/json;q=0.9,*/*;q=0.8",
    }
    body = None
    if data is not None:
        body = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def fetch_bytes(url, timeout=40):
    req = urllib.request.Request(url, headers={"User-Agent": UA,
                                               "Accept": "application/pdf,*/*"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


# --------------------------------------------------------------------------
# Стратегия 1: внутренний JSON-эндпоинт. Быстрее и стабильнее, но недокументирован
# и может измениться без предупреждения — поэтому при любой осечке уходим в HTML.
# --------------------------------------------------------------------------
def search_api(query, page, size=20, catalogs=None, with_found=False):
    payload = {"mode": "articles", "q": query, "size": size,
               "from": (page - 1) * size}
    if catalogs:
        payload["catalogs"] = catalogs
    raw = fetch(SEARCH_API, data=payload)
    data = json.loads(raw)
    items = data.get("articles") or data.get("items") or []
    out = []
    for it in items:
        link = it.get("link") or it.get("url") or ""
        if link and not link.startswith("/"):
            link = "/" + link
        out.append({
            "title": clean(it.get("name") or it.get("title") or ""),
            "url": BASE + link if link else "",
            "journal": clean(it.get("journal") or ""),
            "year": str(it.get("year") or "") or None,
            "authors": clean(it.get("authors") or ""),
            "annotation": clean(it.get("annotation") or it.get("text") or "")[:600],
        })
    if with_found:
        found = data.get("found")
        return out, (int(found) if isinstance(found, (int, str)) and str(found).isdigit() else None)
    return out


def check_catalog_filter(query, catalogs):
    """Сравнить число находок с фильтром и без. Если фильтр не сократил выдачу,
    API его проигнорировал — тогда выдачу нельзя выдавать за отфильтрованную."""
    _, total = search_api(query, 1, size=1, with_found=True)
    _, filtered = search_api(query, 1, size=1, catalogs=catalogs, with_found=True)
    if total is None or filtered is None:
        return None, total, filtered          # API не сообщил числа — проверить нельзя
    return filtered < total, total, filtered


# --------------------------------------------------------------------------
# Стратегия 2: разбор обычной страницы результатов. Медленнее, зато не зависит
# от внутреннего API. Разметка сайта может поменяться — парсер намеренно
# терпимый: цепляется за ссылки вида /article/n/<slug>, остальное добирает
# из окружающего текста.
# --------------------------------------------------------------------------
def parse_html(page_html):
    out, seen = [], set()
    matches = list(ARTICLE_RE.finditer(page_html))
    for idx, match in enumerate(matches):
        href, inner = match.group(1), match.group(2)
        title = clean(inner)
        if not title or href in seen:
            continue
        seen.add(href)
        # хвост после ссылки содержит журнал, год и аннотацию; обрезаем его
        # следующей ссылкой, иначе поля соседних записей слипаются
        stop = matches[idx + 1].start() if idx + 1 < len(matches) else len(page_html)
        tail = clean(page_html[match.end(): min(stop, match.end() + 1200)])
        year = None
        ym = YEAR_RE.search(tail[:200])
        if ym:
            year = ym.group(1)
        out.append({
            "title": title,
            "url": BASE + href,
            "journal": tail[:160] if tail else "",
            "year": year,
            "authors": "",
            "annotation": tail[:600],
        })
    return out


def search_html(query, page):
    params = {"q": query}
    if page > 1:
        params["page"] = page
    return parse_html(fetch(SEARCH_HTML + "?" + urllib.parse.urlencode(params)))


def search(query, pages, strategy, delay, catalogs=None):
    results, seen = [], set()
    used = None
    found = None
    for page in range(1, pages + 1):
        batch = []
        if strategy in ("auto", "api"):
            try:
                batch, f = search_api(query, page, catalogs=catalogs, with_found=True)
                found = found if found is not None else f
                used = used or "api"
            except Exception as exc:
                if strategy == "api" or catalogs:
                    if catalogs:
                        print("[!] Фильтр по перечню работает только через API, а API "
                              f"недоступен ({type(exc).__name__}). Выдачу без фильтра "
                              "за отфильтрованную не выдаю.", file=sys.stderr)
                    raise
                print(f"[i] API недоступен ({type(exc).__name__}), "
                      f"перехожу на разбор HTML", file=sys.stderr)
                strategy = "html"
        if strategy == "html" and not batch:
            batch = search_html(query, page)
            used = used or "html"
        if not batch:
            break
        for item in batch:
            if item["url"] in seen:
                continue
            seen.add(item["url"])
            results.append(item)
        if page < pages:
            time.sleep(delay)
    return results, used, found


def fetch_fulltext(items, limit, save_dir, delay):
    """Для первых limit записей: метки перечней со страницы статьи, текст статьи
    из HTML (если он там есть) и PDF. Ничего не выбрасывает при сбое — помечает."""
    os.makedirs(save_dir, exist_ok=True)
    for n, it in enumerate(items[:limit]):
        if n:
            time.sleep(delay)
        slug = it["url"].rstrip("/").rsplit("/", 1)[-1][:120] or f"item{n + 1}"
        it["labels"], it["text_file"], it["pdf_file"] = [], None, None
        try:
            page = fetch(it["url"])
            it["labels"] = sorted({CATALOG_NAMES[m.lower()] for m in LABEL_RE.findall(page)})
            for rx in BODY_RES:
                m = rx.search(page)
                if m:
                    text = clean(m.group(1))
                    if len(text) > 500:
                        path = os.path.join(save_dir, slug + ".txt")
                        with open(path, "w", encoding="utf-8") as fh:
                            fh.write(it["title"] + "\n" + it["url"] + "\n\n" + text)
                        it["text_file"] = path
                        break
        except Exception as exc:
            it["fulltext_error"] = f"страница статьи: {type(exc).__name__}"
        try:
            time.sleep(delay)
            data = fetch_bytes(it["url"].rstrip("/") + "/pdf")
            if data[:5] == b"%PDF-":
                path = os.path.join(save_dir, slug + ".pdf")
                with open(path, "wb") as fh:
                    fh.write(data)
                it["pdf_file"] = path
        except Exception as exc:
            it["fulltext_error"] = (it.get("fulltext_error", "") + f"; PDF: {type(exc).__name__}").strip("; ")
    return items


def apply_filters(items, since, until):
    if since is None and until is None:
        return items                      # по умолчанию — весь архив
    kept = []
    for it in items:
        year = it.get("year")
        if not year:
            kept.append(it)               # год неизвестен — не выбрасываем
            continue
        y = int(year)
        if since is not None and y < since:
            continue
        if until is not None and y > until:
            continue
        kept.append(it)
    return kept


def to_gost(items):
    """Черновой список источников по ГОСТ Р 7.0.5-2008. Проверяйте вручную:
    авторов и страницы КиберЛенинка в выдаче отдаёт не всегда."""
    lines = []
    for i, it in enumerate(items, 1):
        authors = it.get("authors") or ""
        journal = it.get("journal") or "[журнал не определён]"
        year = it.get("year") or "б. г."
        head = f"{authors} " if authors else ""
        lines.append(
            f"{i}. {head}{it['title']} // {journal}. — {year}. — "
            f"URL: {it['url']} (дата обращения: {time.strftime('%d.%m.%Y')})."
        )
    return "\n".join(lines)


def to_text(items):
    lines = []
    for i, it in enumerate(items, 1):
        year = f" ({it['year']})" if it.get("year") else ""
        lines.append(f"{i}. {it['title']}{year}\n   {it['url']}")
        if "labels" in it:
            lab = ", ".join(it["labels"]) if it["labels"] else "меток на странице нет"
            files = ", ".join(x for x in (it.get("text_file"), it.get("pdf_file")) if x) or "файлы не получены"
            lines.append(f"   перечни: {lab}; полный текст: {files}")
            if it.get("fulltext_error"):
                lines.append(f"   сбой: {it['fulltext_error']}")
        if it.get("annotation"):
            lines.append(f"   {it['annotation'][:220]}")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(
        description="Поиск статей в КиберЛенинке по всему архиву.")
    ap.add_argument("query", help="поисковый запрос")
    ap.add_argument("--pages", type=int, default=3,
                    help="сколько страниц выдачи забрать (по умолчанию 3)")
    ap.add_argument("--since", type=int, default=None,
                    help="не раньше года; по умолчанию без ограничения")
    ap.add_argument("--until", type=int, default=None,
                    help="не позже года; по умолчанию без ограничения")
    ap.add_argument("--format", choices=["text", "json", "gost"], default="text")
    ap.add_argument("--strategy", choices=["auto", "api", "html"], default="auto")
    ap.add_argument("--delay", type=float, default=1.0,
                    help="пауза между страницами в секундах")
    ap.add_argument("--html-file",
                    help="разобрать сохранённую страницу вместо сетевого запроса")
    ap.add_argument("--catalog", default=None,
                    help="только журналы перечней: vak, rsci, scopus (через запятую); "
                         "по умолчанию без фильтра")
    ap.add_argument("--fulltext", type=int, default=0, metavar="N",
                    help="скачать полный текст первых N результатов (не больше 10)")
    ap.add_argument("--save-dir", default="cyberleninka_fulltext",
                    help="куда сохранять полные тексты (по умолчанию ./cyberleninka_fulltext)")
    args = ap.parse_args()

    catalogs = None
    if args.catalog:
        keys = [k.strip().lower() for k in args.catalog.split(",") if k.strip()]
        bad = [k for k in keys if k not in CATALOGS]
        if bad:
            ap.error(f"неизвестный перечень: {', '.join(bad)}; допустимо: vak, rsci, scopus")
        catalogs = [CATALOGS[k] for k in keys]
        if args.html_file or args.strategy == "html":
            ap.error("--catalog работает только через API, без --html-file и --strategy html")
    if args.fulltext > 10:
        ap.error("--fulltext не больше 10: это бесплатный ресурс, не нагружайте его")

    try:
        if args.html_file:
            with open(args.html_file, encoding="utf-8", errors="replace") as fh:
                items, used, found = parse_html(fh.read()), "file", None
        else:
            items, used, found = search(args.query, args.pages, args.strategy,
                                        args.delay, catalogs)
            if catalogs:
                ok, total, filtered = check_catalog_filter(args.query, catalogs)
                if ok is False:
                    print(f"[!] Фильтр --catalog {args.catalog} не сработал: с фильтром "
                          f"{filtered} находок, без фильтра {total}. Вероятно, API "
                          "сменил коды перечней. Выдачу без фильтра за отфильтрованную "
                          "не выдаю.", file=sys.stderr)
                    sys.exit(3)
                if ok is None:
                    print("[!] API не сообщил число находок — проверить фильтр нельзя; "
                          "сверьте метки перечней через --fulltext.", file=sys.stderr)
                # Код мог «съехать» на другой перечень: сверяем метку на странице
                # первой найденной статьи с тем, что запросили.
                if items:
                    try:
                        labels = {m.lower() for m in LABEL_RE.findall(fetch(items[0]["url"]))}
                    except Exception:
                        labels = None
                    wanted = {k.strip().lower() for k in args.catalog.split(",")}
                    if labels and not (labels & wanted):
                        print(f"[!] На странице первой статьи нет метки «{args.catalog}» "
                              f"(есть: {', '.join(sorted(labels))}). Похоже, код перечня "
                              "в API означает другой перечень. Выдачу не отдаю.", file=sys.stderr)
                        sys.exit(3)
                    if labels is not None and not labels:
                        print("[i] Метки перечней на странице статьи не распознаны — "
                              "фильтр проверен только по числу находок.", file=sys.stderr)
    except urllib.error.HTTPError as exc:
        if exc.code in (403, 429):
            print(f"Сайт ответил {exc.code}: запросы блокируются. Это бывает при "
                  f"работе через прокси или из облачной среды. Запустите скрипт "
                  f"с домашней машины, увеличьте --delay, либо сохраните страницу "
                  f"выдачи вручную и разберите её через --html-file.", file=sys.stderr)
            sys.exit(2)
        raise
    except urllib.error.URLError as exc:
        print(f"Сеть недоступна: {exc.reason}", file=sys.stderr)
        sys.exit(2)

    items = apply_filters(items, args.since, args.until)
    if items and args.fulltext:
        items = fetch_fulltext(items, args.fulltext, args.save_dir, args.delay)

    if not items:
        print("Ничего не найдено. Если запрос заведомо рабочий, вероятно, "
              "поменялась разметка сайта — сохраните страницу выдачи и проверьте "
              "через --html-file.", file=sys.stderr)
        sys.exit(1)

    if args.format == "json":
        print(json.dumps(items, ensure_ascii=False, indent=2))
    elif args.format == "gost":
        print(to_gost(items))
    else:
        scope = f"; перечень: {args.catalog}" if catalogs else ""
        total = f", всего в базе по запросу: {found}" if found is not None else ""
        print(f"Найдено: {len(items)} (источник: {used}{total}{scope})\n")
        print(to_text(items))


if __name__ == "__main__":
    main()

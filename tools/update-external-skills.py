#!/usr/bin/env python3
"""Download explicitly allowlisted SKILL.md files; never execute downloaded content.

Config: tools/external-skills.json, {"sources": [{"url": "https://raw.githubusercontent.com/OWNER/REPO/REF/PATH/SKILL.md", "target": "plugins/PLUGIN/skills/SKILL/SKILL.md"}]}.
For GitLab use https://gitlab.com/OWNER/REPO/-/raw/REF/PATH/SKILL.md.
Add sources only after reviewing compatibility and redistribution rights.
This is transport validation, NOT an audit of instructions or prompt injection.
Run from a clean checkout. No private source credentials are transmitted.
"""
import json
import os
from pathlib import Path, PurePosixPath
import tempfile
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

ROOT = Path(__file__).resolve().parent.parent
MAX_BYTES = 128 * 1024

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('Redirects are forbidden')

def main():
    config = json.loads((ROOT / 'tools/external-skills.json').read_text(encoding='utf-8'))
    sources = config['sources']
    if not isinstance(sources, list) or len(sources) > 50:
        raise ValueError('sources must be a list of at most 50 entries')
    opener = build_opener(NoRedirect())
    pending, seen = [], set()
    for item in sources:
        url, target = item['url'], item['target']
        u = urlsplit(url)
        if (u.scheme != 'https' or u.netloc not in ('raw.githubusercontent.com', 'gitlab.com')
                or u.query or u.fragment or not u.path.endswith('/SKILL.md')):
            raise ValueError('Unsupported URL')
        if u.netloc == 'gitlab.com' and '/-/raw/' not in u.path:
            raise ValueError('Expected GitLab raw URL')
        p = PurePosixPath(target)
        parts = p.parts
        if (len(parts) != 5 or parts[0] != 'plugins' or parts[2] != 'skills'
                or parts[4] != 'SKILL.md' or '..' in parts or p.is_absolute()
                or '\\' in target or target != str(p) or target in seen):
            raise ValueError('Invalid or duplicate target')
        seen.add(target)
        dest = ROOT.joinpath(*parts)
        if any(parent.is_symlink() for parent in [dest, *dest.parents]):
            raise ValueError('Symlink target forbidden')
        dest.resolve().relative_to(ROOT)
        req = Request(url, headers={'User-Agent': 'monakhov-skills-updater/1'})
        with opener.open(req, timeout=30) as response:
            data = response.read(MAX_BYTES + 1)
        if not data or len(data) > MAX_BYTES:
            raise ValueError('Empty or oversized skill')
        text = data.decode('utf-8')
        lines = text.splitlines()
        if (not lines or lines[0] != '---' or '---' not in lines[1:]
                or '\x00' in text):
            raise ValueError('Expected UTF-8 Markdown with YAML front matter')
        end = lines.index('---', 1)
        if not any(line.startswith('name:') for line in lines[1:end]):
            raise ValueError('Missing skill name')
        if not any(line.startswith('description:') for line in lines[1:end]):
            raise ValueError('Missing skill description')
        if not dest.exists() or dest.read_bytes() != data:
            pending.append((dest, data))
    # Finish every download and validation before writing any candidate.
    for dest, data in pending:
        dest.parent.mkdir(parents=True, exist_ok=True)
        fd, temp = tempfile.mkstemp(dir=dest.parent, prefix='.skill-update-')
        try:
            with os.fdopen(fd, 'wb') as out:
                out.write(data)
            os.replace(temp, dest)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)
    print(f'Sources: {len(sources)}; changed files: {len(pending)}')

if __name__ == '__main__':
    main()

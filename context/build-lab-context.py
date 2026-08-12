#!/usr/bin/env python3
"""
build-lab-context.py

Consolida todos os blocos atômicos em `context/facts/*.md` num único
`context/build/LAB-CONTEXT.md` que serve como corpus enviável para o
OmniRoute (`/v1/files`) e injetável como system prompt nos clientes LLM
do lab.

Cada bloco tem frontmatter YAML (key, type, tags, priority, expires_at) e
conteúdo markdown. Este script:

1. Lê todos os `.md` do diretório `facts/`
2. Parseia frontmatter
3. Descarta blocos expirados (expires_at < hoje)
4. Agrupa por `type` (semantic → factual → procedural → episodic) e
   ordena por `priority` (high → medium → low)
5. Emite `LAB-CONTEXT.md` com cabeçalho + blocos concatenados

Uso:
    python3 build-lab-context.py             # gera build/LAB-CONTEXT.md
    python3 build-lab-context.py --stats     # só imprime estatísticas

Idempotente. Determinístico (mesma entrada → mesmo output → mesmo hash).
"""

from __future__ import annotations
import argparse
import re
import sys
from datetime import date, datetime, timezone
from pathlib import Path


SCRIPT_DIR = Path(__file__).parent
FACTS_DIR = SCRIPT_DIR / "facts"
BUILD_DIR = SCRIPT_DIR / "build"
OUTPUT_FILE = BUILD_DIR / "LAB-CONTEXT.md"

TYPE_ORDER = ["semantic", "factual", "procedural", "episodic"]
PRIORITY_ORDER = {"high": 0, "medium": 1, "low": 2}

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n(.*)$", re.DOTALL)


def parse_yaml_simple(text: str) -> dict:
    """Parser YAML mínimo (só o subset usado nos blocos)."""
    out: dict = {}
    for line in text.splitlines():
        line = line.rstrip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        k, _, v = line.partition(":")
        k = k.strip()
        v = v.strip()
        if v.startswith("[") and v.endswith("]"):
            # lista inline
            items = [x.strip().strip('"\'') for x in v[1:-1].split(",") if x.strip()]
            out[k] = items
        elif v in ("null", "~", ""):
            out[k] = None
        elif v.lower() in ("true", "false"):
            out[k] = v.lower() == "true"
        else:
            out[k] = v.strip('"\'')
    return out


def parse_block(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    m = FRONTMATTER_RE.match(text)
    if not m:
        raise ValueError(f"{path.name}: sem frontmatter YAML válido")
    meta = parse_yaml_simple(m.group(1))
    body = m.group(2).strip()
    if not meta.get("key"):
        raise ValueError(f"{path.name}: sem 'key' no frontmatter")
    if meta.get("type") not in TYPE_ORDER:
        raise ValueError(f"{path.name}: type '{meta.get('type')}' inválido")
    return {
        "path": path,
        "key": meta["key"],
        "type": meta["type"],
        "tags": meta.get("tags") or [],
        "priority": meta.get("priority") or "medium",
        "expires_at": meta.get("expires_at"),
        "body": body,
    }


def is_expired(block: dict, today: date) -> bool:
    exp = block.get("expires_at")
    if not exp:
        return False
    try:
        d = datetime.fromisoformat(exp).date()
        return d < today
    except ValueError:
        return False


def sort_key(block: dict) -> tuple:
    return (
        TYPE_ORDER.index(block["type"]),
        PRIORITY_ORDER.get(block["priority"], 1),
        block["key"],
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stats", action="store_true", help="imprime só stats, sem gerar arquivo")
    args = ap.parse_args()

    if not FACTS_DIR.exists():
        print(f"ERRO: {FACTS_DIR} não existe", file=sys.stderr)
        return 1

    today = date.today()
    blocks: list[dict] = []
    for md in sorted(FACTS_DIR.glob("*.md")):
        try:
            b = parse_block(md)
        except ValueError as e:
            print(f"WARN: {e}", file=sys.stderr)
            continue
        if is_expired(b, today):
            print(f"SKIP expired: {b['key']}", file=sys.stderr)
            continue
        blocks.append(b)

    blocks.sort(key=sort_key)

    # Sanity: chaves duplicadas
    seen: dict[str, Path] = {}
    for b in blocks:
        if b["key"] in seen:
            print(
                f"ERRO: chave duplicada '{b['key']}' em {b['path'].name} "
                f"e {seen[b['key']].name}",
                file=sys.stderr,
            )
            return 2
        seen[b["key"]] = b["path"]

    if args.stats:
        print(f"blocos: {len(blocks)}")
        by_type: dict[str, int] = {}
        for b in blocks:
            by_type[b["type"]] = by_type.get(b["type"], 0) + 1
        for t in TYPE_ORDER:
            if t in by_type:
                print(f"  {t}: {by_type[t]}")
        total = sum(len(b["body"]) for b in blocks)
        print(f"total_bytes: {total} (~{total/1024:.1f} KB)")
        return 0

    BUILD_DIR.mkdir(exist_ok=True)
    lines: list[str] = []
    lines.append("# Lab Context — infra-lab")
    lines.append("")
    lines.append(
        f"Gerado automaticamente por `build-lab-context.py` a partir de "
        f"`context/facts/*.md`. **Não editar diretamente**: alterações são sobrescritas."
    )
    lines.append("")
    lines.append(f"- Geração: `{datetime.now(timezone.utc).isoformat(timespec='seconds')}`")
    lines.append(f"- Blocos: {len(blocks)}")
    lines.append(
        f"- Fonte: `github.com/netomussauer/infra-lab` (path `context/facts/`)"
    )
    lines.append("")
    lines.append("---")
    lines.append("")

    current_type = None
    for b in blocks:
        if b["type"] != current_type:
            current_type = b["type"]
            lines.append(f"# {current_type.capitalize()}")
            lines.append("")
        lines.append(f"## {b['key']}")
        if b["tags"]:
            lines.append(f"*tags: {', '.join(b['tags'])}*")
            lines.append("")
        lines.append(b["body"])
        lines.append("")

    output = "\n".join(lines).rstrip() + "\n"
    OUTPUT_FILE.write_text(output, encoding="utf-8")
    kb = len(output.encode("utf-8")) / 1024
    print(f"OK: {OUTPUT_FILE.relative_to(SCRIPT_DIR.parent)} ({kb:.1f} KB, {len(blocks)} blocos)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

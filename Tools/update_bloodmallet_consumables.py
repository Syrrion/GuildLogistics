#!/usr/bin/env python3
"""Fetch potions & phials (consumables) data from bloodmallet.com and embed as Lua.

Generates two files per class/spec under Data/SimCraft/<class>/<spec>/ :
  - flacons.lua (phials dataset)
  - potions.lua (potions dataset)

Each file defines a global namespace key: ns.Consum_<class>_<spec>_<kind>
Where kind is 'flacons' or 'potions'. (French naming retained for phials per request.)

Usage:
  python Tools/update_bloodmallet_consumables.py [--dry-run]

Optional environment variable BLM_BASE_URL_CONS to override the base template.
"""
from __future__ import annotations
import argparse, json, os, random, sys, textwrap, time
from pathlib import Path
import urllib.request, urllib.error

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_ROOT = BASE_DIR / "Data" / "SimCraft"
# Endpoint templates
# e.g. https://bloodmallet.com/chart/get/phials/castingpatchwerk/death_knight/blood
DEFAULT_URL_TEMPLATE = "https://bloodmallet.com/chart/get/{kind}/castingpatchwerk/{class_slug}/{spec_slug}"
KINDS = {"flacons": "phials", "potions": "potions"}

HEADER = textwrap.dedent(
    """    local ADDON, ns = ...
    local Tr = ns and ns.Tr
    local GLOG, UI = ns and ns.GLOG, ns and ns.UI
    local UI = ns and ns.UI

    """
)

def build_lua_block(class_slug: str, spec_slug: str, kind: str, payload: dict) -> str:
    json_blob = json.dumps(payload, indent=4, ensure_ascii=False)
    key = f"ns.Consum_{class_slug}_{spec_slug}_{kind}"
    return f"{HEADER}{key} = [[\n{json_blob}\n]]\n"


def fetch_payload(url: str, *, retries: int = 3, backoff: float = 1.5) -> dict:
    headers = {
        "User-Agent": "GuildLogistics-ConsumablesFetcher/1.0 (+https://github.com/Ysendril/GuildLogistics)",
        "Accept": "application/json",
    }
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:  # nosec B310
                charset = resp.headers.get_content_charset() or "utf-8"
                raw = resp.read().decode(charset)
            try:
                return json.loads(raw)
            except json.JSONDecodeError as exc:  # pragma: no cover
                raise RuntimeError(f"Invalid JSON from {url}: {exc}") from exc
        except urllib.error.HTTPError as exc:  # pragma: no cover
            if attempt < retries and exc.code in {403, 429, 500, 502, 503, 504}:
                delay = backoff ** attempt + random.uniform(0, 0.5)
                print(f"[retry] HTTP {exc.code} {url} in {delay:.2f}s ({attempt}/{retries})")
                time.sleep(delay)
                continue
            raise RuntimeError(f"HTTP {exc.code} fetching {url}") from exc
        except urllib.error.URLError as exc:  # pragma: no cover
            if attempt < retries:
                delay = backoff ** attempt + random.uniform(0, 0.5)
                print(f"[retry] URL error {exc.reason} {url} in {delay:.2f}s ({attempt}/{retries})")
                time.sleep(delay)
                continue
            raise RuntimeError(f"Failed to reach {url}: {exc.reason}") from exc


def update_spec(class_slug: str, spec_dir: Path, url_template: str, dry_run: bool = False):
    spec_slug = spec_dir.name
    for kind, remote_kind in KINDS.items():
        url = url_template.format(kind=remote_kind, class_slug=class_slug, spec_slug=spec_slug)
        payload = fetch_payload(url)
        lua_content = build_lua_block(class_slug, spec_slug, kind, payload)
        out_file = spec_dir / f"{kind}.lua"
        if dry_run:
            print(f"[dry-run] Would write {out_file.relative_to(BASE_DIR)}")
        else:
            out_file.write_text(lua_content, encoding="utf-8")
            print(f"[update] {out_file.relative_to(BASE_DIR)}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true", help="show actions without writing files")
    ap.add_argument("--base-url", default=os.environ.get("BLM_BASE_URL_CONS", DEFAULT_URL_TEMPLATE), help="override URL template")
    args = ap.parse_args(argv)

    if not DATA_ROOT.is_dir():
        ap.error(f"Data root not found: {DATA_ROOT}")

    for class_dir in sorted(DATA_ROOT.iterdir()):
        if not class_dir.is_dir():
            continue
        class_slug = class_dir.name
        for spec_dir in sorted(class_dir.iterdir()):
            if not spec_dir.is_dir():
                continue
            update_spec(class_slug, spec_dir, args.base_url, dry_run=args.dry_run)

    return 0

if __name__ == "__main__":
    sys.exit(main())

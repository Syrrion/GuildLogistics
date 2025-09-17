#!/usr/bin/env python3
"""Fetch trinket simulation data from bloodmallet.com and update local Lua datasets.

The script walks through Data/SimCraft/<class>/<spec> directories, downloads the
JSON payload for each specialization and rewrites the Lua files (1.lua, 3.lua, 5.lua)
with a fresh copy of the data embedded as a literal string.

Usage:
    python Tools/update_simc_data.py [--dry-run]

Set BLM_BASE_URL to override the bloodmallet endpoint for testing.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import textwrap
import urllib.error
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_ROOT = BASE_DIR / "Data" / "SimCraft"
DEFAULT_URL_TEMPLATE = "https://bloodmallet.com/chart/get/trinkets/{endpoint}/{class_slug}/{spec_slug}"
TARGET_ENDPOINTS = {
    "1": "castingpatchwerk",
    "3": "castingpatchwerk3",
    "5": "castingpatchwerk5",
}

HEADER = textwrap.dedent(
    """    local ADDON, ns = ...
    local Tr = ns and ns.Tr
    local GLOG, UI = ns and ns.GLOG, ns and ns.UI
    local UI = ns and ns.UI

    """
)


def build_lua_block(class_slug: str, spec_slug: str, target: str, payload: dict) -> str:
    json_blob = json.dumps(payload, indent=4, ensure_ascii=False)
    key = f"ns.Datas_{class_slug}_{spec_slug}_{target}"
    return f"{HEADER}{key} = [[\n{json_blob}\n]]\n"


def fetch_payload(url: str) -> dict:
    try:
        with urllib.request.urlopen(url) as response:  # nosec B310 - trusted endpoint
            charset = response.headers.get_content_charset() or "utf-8"
            raw = response.read().decode(charset)
    except urllib.error.HTTPError as exc:  # pragma: no cover - network errors
        raise RuntimeError(f"HTTP {exc.code} while fetching {url}") from exc
    except urllib.error.URLError as exc:  # pragma: no cover
        raise RuntimeError(f"Failed to reach {url}: {exc.reason}") from exc

    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JSON returned by {url}: {exc}") from exc


def update_spec(class_slug: str, spec_path: Path, url_template: str, dry_run: bool = False) -> None:
    spec_slug = spec_path.name
    targets = sorted(child for child in spec_path.glob("*.lua"))
    if not targets:
        print(f"[warn] No target files found under {spec_path}")
        return

    for lua_file in targets:
        target = lua_file.stem
        endpoint = TARGET_ENDPOINTS.get(target)
        if not endpoint:
            print(f"[warn] Unknown target '{target}' in {spec_path}, skipping")
            continue
        url = url_template.format(endpoint=endpoint, class_slug=class_slug, spec_slug=spec_slug)
        payload = fetch_payload(url)
        lua_content = build_lua_block(class_slug, spec_slug, target, payload)
        display_path = lua_file.relative_to(BASE_DIR)
        if dry_run:
            print(f"[dry-run] Would update {display_path}")
            continue
        lua_file.write_text(lua_content, encoding="utf-8")
        print(f"[update] {display_path}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="fetch data and show targets without rewriting files",
    )
    parser.add_argument(
        "--base-url",
        default=os.environ.get("BLM_BASE_URL", DEFAULT_URL_TEMPLATE),
        help="override the bloodmallet URL template",
    )
    args = parser.parse_args(argv)

    if not DATA_ROOT.is_dir():
        parser.error(f"Data directory not found: {DATA_ROOT}")

    updated = 0
    for class_dir in sorted(DATA_ROOT.iterdir()):
        if not class_dir.is_dir():
            continue
        class_slug = class_dir.name
        for spec_dir in sorted(class_dir.iterdir()):
            if not spec_dir.is_dir():
                continue
            update_spec(class_slug, spec_dir, args.base_url, dry_run=args.dry_run)
            updated += 1

    if updated == 0:
        print("[warn] No specialisations processed. Check directory structure.")

    return 0


if __name__ == "__main__":
    sys.exit(main())

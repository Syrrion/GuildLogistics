#!/usr/bin/env python3
"""Fetch SimulationCraft trinket datasets and (optionally) Bloodmallet consumables (potions/phials) in a SINGLE pass.

Features:
  * Refresh trinket datasets for targets (1,3,5) under Data/SimCraft/<class>/<spec>/
  * (Optional) Also fetch potions & phials and write flacons.lua / potions.lua adjacent to trinket files
  * Robust retry & backoff for HTTP and network transient errors
  * Deterministic file naming; safe for git diff review

Why merged? Eliminates the need for a second Python invocation (previously update_bloodmallet_consumables.py)
and ensures both trinkets and consumables update atomically for each spec in CI.

Usage:
    python Tools/update_simc_data.py [--dry-run] [--with-consumables]

Environment variables:
    BLM_BASE_URL              Override trinkets URL template
    WITH_CONSUMABLES=1        Implicitly enable --with-consumables
    BLM_BASE_URL_CONS         Override consumables URL template

Backward compatibility: The separate script is deprecated and its logic fully inlined here.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
import textwrap
import time
import urllib.error
import urllib.request
from pathlib import Path
import subprocess  # retained for potential future parallelization (not used now)

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_ROOT = BASE_DIR / "Data" / "SimCraft"
DEFAULT_URL_TEMPLATE = "https://bloodmallet.com/chart/get/trinkets/{endpoint}/{class_slug}/{spec_slug}"
DEFAULT_CONS_URL_TEMPLATE = "https://bloodmallet.com/chart/get/{kind}/castingpatchwerk/{class_slug}/{spec_slug}"
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

CONSUMABLE_KINDS = {"flacons": "phials", "potions": "potions"}


def build_lua_block_trinket(class_slug: str, spec_slug: str, target: str, payload: dict) -> str:
    json_blob = json.dumps(payload, indent=4, ensure_ascii=False)
    key = f"ns.Datas_{class_slug}_{spec_slug}_{target}"
    return f"{HEADER}{key} = [[\n{json_blob}\n]]\n"


def build_lua_block_consumable(class_slug: str, spec_slug: str, kind: str, payload: dict) -> str:
    json_blob = json.dumps(payload, indent=4, ensure_ascii=False)
    key = f"ns.Consum_{class_slug}_{spec_slug}_{kind}"
    return f"{HEADER}{key} = [[\n{json_blob}\n]]\n"


def fetch_payload(url: str, *, retries: int = 3, backoff: float = 1.5) -> dict:
    headers = {
        "User-Agent": "GuildLogistics-DataFetcher/1.0 (+https://github.com/Ysendril/GuildLogistics)",
        "Accept": "application/json",
    }

    for attempt in range(1, retries + 1):
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as response:  # nosec B310 - trusted endpoint
                charset = response.headers.get_content_charset() or "utf-8"
                raw = response.read().decode(charset)
            try:
                return json.loads(raw)
            except json.JSONDecodeError as exc:
                raise RuntimeError(f"Invalid JSON returned by {url}: {exc}") from exc
        except urllib.error.HTTPError as exc:  # pragma: no cover - network errors
            if attempt < retries and exc.code in {403, 429, 500, 502, 503, 504}:
                delay = backoff ** attempt + random.uniform(0, 0.5)
                print(f"[retry] HTTP {exc.code} for {url}, retrying in {delay:.2f}s (attempt {attempt}/{retries})")
                time.sleep(delay)
                continue
            raise RuntimeError(f"HTTP {exc.code} while fetching {url}") from exc
        except urllib.error.URLError as exc:  # pragma: no cover
            if attempt < retries:
                delay = backoff ** attempt + random.uniform(0, 0.5)
                print(f"[retry] URLError for {url}: {exc.reason}, retrying in {delay:.2f}s (attempt {attempt}/{retries})")
                time.sleep(delay)
                continue
            raise RuntimeError(f"Failed to reach {url}: {exc.reason}") from exc


def update_spec(
    class_slug: str,
    spec_path: Path,
    trinket_url_template: str,
    *,
    dry_run: bool = False,
    with_consumables: bool = False,
    consumable_url_template: str | None = None,
) -> None:
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
        url = trinket_url_template.format(endpoint=endpoint, class_slug=class_slug, spec_slug=spec_slug)
        payload = fetch_payload(url)
        lua_content = build_lua_block_trinket(class_slug, spec_slug, target, payload)
        display_path = lua_file.relative_to(BASE_DIR)
        if dry_run:
            print(f"[dry-run] Would update {display_path}")
            continue
        lua_file.write_text(lua_content, encoding="utf-8")
        print(f"[update] {display_path}")

    if with_consumables:
        # Write (or overwrite) flacons.lua and potions.lua
        for kind, remote_kind in CONSUMABLE_KINDS.items():
            url_tmpl = consumable_url_template or DEFAULT_CONS_URL_TEMPLATE
            url = url_tmpl.format(kind=remote_kind, class_slug=class_slug, spec_slug=spec_slug)
            payload = fetch_payload(url)
            lua_content = build_lua_block_consumable(class_slug, spec_slug, kind, payload)
            out_file = spec_path / f"{kind}.lua"
            rel = out_file.relative_to(BASE_DIR)
            if dry_run:
                print(f"[dry-run] Would update {rel}")
            else:
                out_file.write_text(lua_content, encoding="utf-8")
                print(f"[update] {rel}")


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
        help="override the bloodmallet trinkets URL template",
    )
    parser.add_argument(
        "--with-consumables",
        action="store_true",
        help="also refresh potions & phials (writes flacons.lua & potions.lua)",
    )
    parser.add_argument(
        "--consumables-base-url",
        default=os.environ.get("BLM_BASE_URL_CONS", DEFAULT_CONS_URL_TEMPLATE),
        help="override consumables URL template (phials/potions)",
    )
    args = parser.parse_args(argv)

    if (not args.with_consumables) and os.environ.get("WITH_CONSUMABLES") == "1":
        args.with_consumables = True

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
            update_spec(
                class_slug,
                spec_dir,
                args.base_url,
                dry_run=args.dry_run,
                with_consumables=args.with_consumables,
                consumable_url_template=args.consumables_base_url,
            )
            updated += 1

    if updated == 0:
        print("[warn] No specialisations processed. Check directory structure.")

    # No subprocess chaining needed anymore; logic merged inline.

    return 0


if __name__ == "__main__":
    sys.exit(main())

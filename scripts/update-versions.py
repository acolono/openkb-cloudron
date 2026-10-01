#!/usr/bin/env python3
"""Adds (or refreshes) the current manifest version in CloudronVersions.json.

Usage: scripts/update-versions.py IMAGE [--state published|testing]

Follows https://docs.cloudron.io/packaging/versions: every entry embeds the full
manifest with file:// references inlined and `dockerImage` set. Earlier
versions are kept, which is what lets installed apps update.
"""
import argparse
import json
import re
import sys
from email.utils import formatdate
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REQUIRED = ["id", "title", "description", "tagline", "website", "tags", "changelog",
            "mediaLinks", "healthCheckPath", "iconUrl", "packagerName", "packagerUrl"]


def changelog_section(text: str, version: str) -> str:
    m = re.search(rf"^\[{re.escape(version)}\]\s*\n(.*?)(?=^\[|\Z)", text, re.M | re.S)
    if not m or not m.group(1).strip():
        sys.exit(f"CHANGELOG has no [{version}] section")
    return m.group(1).strip()


def resolve(manifest: dict) -> dict:
    out = dict(manifest)
    for key in ("description", "postInstallMessage", "changelog"):
        value = out.get(key)
        if isinstance(value, str) and value.startswith("file://"):
            text = (ROOT / value[len("file://"):]).read_text()
            out[key] = changelog_section(text, out["version"]) if key == "changelog" else text.strip()
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--state", default="published", choices=["published", "testing"])
    args = ap.parse_args()

    manifest = resolve(json.loads((ROOT / "CloudronManifest.json").read_text()))
    manifest["dockerImage"] = args.image
    missing = [k for k in REQUIRED if not manifest.get(k)]
    if missing:
        sys.exit(f"manifest lacks publish fields: {', '.join(missing)}")

    path = ROOT / "CloudronVersions.json"
    catalog = json.loads(path.read_text()) if path.exists() else {"stable": True, "versions": {}}
    version = manifest["version"]
    now = formatdate(usegmt=True)
    previous = catalog["versions"].get(version, {})
    catalog["versions"][version] = {
        "manifest": manifest,
        "creationDate": previous.get("creationDate", now),
        "ts": now,
        "publishState": args.state,
    }
    path.write_text(json.dumps(catalog, indent=2) + "\n")
    print(f"{path.name}: {version} -> {args.image} ({args.state})")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Build GitHub release notes for a tag from CHANGELOG.md.

The workflow's generate_release_notes only produces a compare link, which
tells a user nothing about what changed. This turns the hand-written
CHANGELOG entry into the release body instead, so "What's new" actually
lists the features and fixes.

Usage:
    python3 scripts/release_notes.py v1.5.2 > notes.md
    python3 scripts/release_notes.py v1.5.2 --previous v1.5.1
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO = "Code-Stride/VibeTube"

# Section heading -> (emoji, human title). Order defines output order.
SECTIONS: dict[str, tuple[str, str]] = {
    "added": ("✨", "New"),
    "changed": ("🔧", "Improved"),
    "fixed": ("🐛", "Fixed"),
    "security": ("🔒", "Security"),
    "removed": ("🗑️", "Removed"),
    "deprecated": ("⚠️", "Deprecated"),
}


def parse_changelog(text: str, version: str) -> tuple[str, dict[str, list[str]]]:
    """Return (date, {section: [bullet, ...]}) for the given version."""
    # Match "## [1.5.2] - 2026-07-31" up to the next "## " heading.
    pattern = (
        r"^##\s*\[?"
        + re.escape(version)
        + r"\]?\s*-?\s*(?P<date>[\d-]*)\s*$(?P<body>.*?)(?=^##\s|\Z)"
    )
    m = re.search(pattern, text, re.MULTILINE | re.DOTALL)
    if not m:
        raise SystemExit(f"No CHANGELOG entry found for version {version}")

    date = m.group("date").strip()
    body = m.group("body")

    sections: dict[str, list[str]] = {}
    current: str | None = None
    buffer: list[str] = []

    def flush() -> None:
        if current and buffer:
            # Join wrapped continuation lines into single bullets.
            bullets: list[str] = []
            for line in buffer:
                if line.startswith("- "):
                    bullets.append(line[2:].strip())
                elif bullets and line.strip():
                    bullets[-1] += " " + line.strip()
            if bullets:
                sections.setdefault(current, []).extend(
                    b.strip() for b in bullets if b.strip()
                )

    for line in body.splitlines():
        heading = re.match(r"^###\s+(.*?)\s*$", line)
        if heading:
            flush()
            buffer = []
            current = heading.group(1).strip().lower()
            continue
        if line.strip():
            buffer.append(line)
        elif buffer and not line.strip():
            buffer.append("")
    flush()
    return date, sections


def strip_markdown(s: str) -> str:
    """Plain-text length check shouldn't count markdown syntax."""
    return re.sub(r"[*`_\[\]]", "", s)


def build_notes(version: str, date: str, sections: dict[str, list[str]],
                previous: str | None) -> str:
    out: list[str] = []

    # Lead with a one-line summary of what the user gains. Prefer a new
    # feature, then an improvement — leading on a bug description would open
    # the page on a negative.
    counts = {k: len(v) for k, v in sections.items() if v}
    summary_bits = []
    for key, (_, title) in SECTIONS.items():
        n = counts.get(key)
        if n:
            summary_bits.append(f"{n} {title.lower()}")
    if summary_bits:
        out.append(f"_This release: {', '.join(summary_bits)}._")
        out.append("")

    for key, (emoji, title) in SECTIONS.items():
        bullets = sections.get(key)
        if not bullets:
            continue
        out.append(f"## {emoji} {title}")
        out.append("")
        for b in bullets:
            out.append(f"- {b}")
        out.append("")

    out.append("---")
    out.append("")
    out.append("### 📦 Install")
    out.append("")
    out.append(
        f"Download `VibeTube-release.apk` below and open it on your device. "
        f"You may need to allow installs from unknown sources."
    )
    out.append("")
    out.append(
        "This build is signed with the same key as previous releases, so it "
        "installs over an existing copy as a normal update."
    )
    out.append("")
    if previous:
        out.append(
            f"**Full changelog**: "
            f"https://github.com/{REPO}/compare/{previous}...{version}"
        )
    return "\n".join(out).rstrip() + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("tag", help="release tag, e.g. v1.5.2")
    ap.add_argument("--previous", help="previous tag for the compare link")
    ap.add_argument(
        "--changelog", default="CHANGELOG.md", help="path to CHANGELOG.md"
    )
    args = ap.parse_args()

    version = args.tag.lstrip("vV")
    path = Path(args.changelog)
    if not path.exists():
        raise SystemExit(f"{path} not found")

    date, sections = parse_changelog(path.read_text(encoding="utf-8"), version)
    if not sections:
        raise SystemExit(f"CHANGELOG entry for {version} has no ### sections")

    sys.stdout.write(build_notes(args.tag, date, sections, args.previous))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

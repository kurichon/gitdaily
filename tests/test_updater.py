#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPDATER = ROOT / "repo-updater" / "update_existing_repo.py"

if not UPDATER.exists():
    print("[SKIP] local-only repo updater is not present in this checkout")
    raise SystemExit(0)

spec = importlib.util.spec_from_file_location("repo_updater", UPDATER)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    source = base / "source"
    target = base / "target"
    source.mkdir()
    target.mkdir()
    (target / ".git").mkdir()
    (target / "activity").mkdir()
    (source / "VERSION").write_text("2\n")
    (source / "README.md").write_text("new\n")
    (source / "added.txt").write_text("added\n")
    (source / "activity").mkdir()
    (source / "activity" / "new.md").write_text("must not copy\n")
    (target / "VERSION").write_text("1\n")
    (target / "README.md").write_text("old\n")
    (target / "activity" / "keep.md").write_text("keep\n")
    (target / "target-only.txt").write_text("keep me\n")

    additions, updates, unchanged = module.compare(source, target)
    assert Path("added.txt") in additions
    assert Path("README.md") in updates
    assert Path("VERSION") in updates
    backup = module.apply(source, target, additions, updates)
    assert (target / "README.md").read_text() == "new\n"
    assert (target / "added.txt").read_text() == "added\n"
    assert (target / "target-only.txt").read_text() == "keep me\n"
    assert (target / "activity" / "keep.md").read_text() == "keep\n"
    assert not (target / "activity" / "new.md").exists()
    assert (target / ".git").is_dir()
    assert backup is not None
    assert (backup / "README.md").read_text() == "old\n"

print("[PASS] repository updater overwrites by hash while preserving .git/activity/target-only files")

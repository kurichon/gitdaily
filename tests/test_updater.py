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
    (source / ".github" / "workflows").mkdir(parents=True)
    (source / ".github" / "workflows" / "ci.yml").write_text("name: CI\n")
    (target / "VERSION").write_text("1\n")
    (target / "README.md").write_text("old\n")
    (target / "activity" / "keep.md").write_text("keep\n")
    (target / "target-only.txt").write_text("keep me\n")

    additions, updates, unchanged = module.compare(source, target)
    assert Path("added.txt") in additions
    assert Path("README.md") in updates
    assert Path("VERSION") in updates
    assert Path(".github/workflows/ci.yml") in additions
    backup = module.apply(source, target, additions, updates)
    assert (target / "README.md").read_text() == "new\n"
    assert (target / "added.txt").read_text() == "added\n"
    assert (target / ".github" / "workflows" / "ci.yml").read_text() == "name: CI\n"
    assert (target / "target-only.txt").read_text() == "keep me\n"
    assert (target / "activity" / "keep.md").read_text() == "keep\n"
    assert not (target / "activity" / "new.md").exists()
    assert (target / ".git").is_dir()
    assert backup is not None
    assert (backup / "README.md").read_text() == "old\n"


# Symlink safety: preview/apply must never follow a target symlink outside the repo.
with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    source = base / "source"
    target = base / "target"
    outside = base / "outside.txt"
    source.mkdir()
    target.mkdir()
    (target / ".git").mkdir()
    (source / "VERSION").write_text("2\n")
    (source / "README.md").write_text("new\n")
    outside.write_text("do not overwrite\n")
    (target / "README.md").symlink_to(outside)
    try:
        module.compare(source, target)
    except RuntimeError as exc:
        assert "symlink" in str(exc).lower()
    else:
        raise AssertionError("target symlink was not refused")
    assert outside.read_text() == "do not overwrite\n"

# Release sources containing symlinks are also refused.
with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    source = base / "source"
    target = base / "target"
    outside = base / "outside.txt"
    source.mkdir()
    target.mkdir()
    (target / ".git").mkdir()
    (source / "VERSION").write_text("2\n")
    outside.write_text("outside\n")
    (source / "README.md").symlink_to(outside)
    try:
        module.compare(source, target)
    except RuntimeError as exc:
        assert "symlink" in str(exc).lower()
    else:
        raise AssertionError("source symlink was not refused")

print("[PASS] repository updater preserves .git/activity, carries .github workflows, and refuses symlinks")

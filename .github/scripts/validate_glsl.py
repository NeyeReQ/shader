#!/usr/bin/env python3
"""Expand Iris shader includes and run glslangValidator on every shader stage."""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHADERS = ROOT / "shaders"
INCLUDE_RE = re.compile(r'^\s*#include\s+"([^"]+)"\s*$', re.MULTILINE)


def expand_includes(source: str, current_file: Path, stack: tuple[Path, ...] = ()) -> str:
    def replace(match: re.Match[str]) -> str:
        include_name = match.group(1).lstrip("/")
        include_path = (SHADERS / include_name).resolve()

        if not include_path.is_relative_to(SHADERS.resolve()):
            raise ValueError(f"Include escapes shaders directory: {include_name}")
        if include_path in stack:
            raise ValueError(f"Recursive shader include: {include_path}")
        if not include_path.is_file():
            raise FileNotFoundError(f"Missing shader include: {include_path}")

        included = include_path.read_text(encoding="utf-8")
        return expand_includes(included, include_path, (*stack, include_path))

    return INCLUDE_RE.sub(replace, source)


def main() -> int:
    validator = subprocess.run(
        ["glslangValidator", "--version"],
        check=False,
        capture_output=True,
        text=True,
    )
    if validator.returncode != 0:
        print("glslangValidator is required (install glslang-tools).", file=sys.stderr)
        return 2

    stage_map = {".vsh": "vert", ".fsh": "frag"}
    shader_files = sorted(
        path for path in SHADERS.rglob("*")
        if path.is_file() and path.suffix in stage_map
    )
    if not shader_files:
        print("No shader stages found.", file=sys.stderr)
        return 2

    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="aetheris-glsl-") as temp_dir:
        temp_root = Path(temp_dir)
        for shader_path in shader_files:
            try:
                expanded = expand_includes(
                    shader_path.read_text(encoding="utf-8"),
                    shader_path,
                    (shader_path.resolve(),),
                )
                temp_path = temp_root / f"{shader_path.stem}_{stage_map[shader_path.suffix]}{shader_path.suffix}"
                temp_path.write_text(expanded, encoding="utf-8")
                result = subprocess.run(
                    ["glslangValidator", "-S", stage_map[shader_path.suffix], str(temp_path)],
                    check=False,
                    capture_output=True,
                    text=True,
                )
                if result.returncode != 0:
                    failures.append(
                        f"{shader_path.relative_to(ROOT)}:\n{result.stdout}{result.stderr}"
                    )
                else:
                    print(f"PASS {shader_path.relative_to(ROOT)}")
            except (OSError, ValueError) as exc:
                failures.append(f"{shader_path.relative_to(ROOT)}: {exc}")

    if failures:
        print("\n\n".join(failures), file=sys.stderr)
        return 1

    print(f"Validated {len(shader_files)} GLSL stages.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

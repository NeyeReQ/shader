#!/usr/bin/env python3
"""Expand Iris shader includes, compile GLSL stages, and link matching pairs."""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHADERS = ROOT / "shaders"
INCLUDE_RE = re.compile(r'^\s*#include\s+"([^"]+)"\s*$', re.MULTILINE)
STAGES = {".vsh": "vert", ".fsh": "frag"}


def expand_includes(source: str, stack: tuple[Path, ...] = ()) -> str:
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
        return expand_includes(included, (*stack, include_path))

    return INCLUDE_RE.sub(replace, source)


def run_validator(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, check=False, capture_output=True, text=True)


def main() -> int:
    version = run_validator(["glslangValidator", "--version"])
    if version.returncode != 0:
        print("glslangValidator is required (install glslang-tools).", file=sys.stderr)
        return 2

    shader_files = sorted(
        path for path in SHADERS.rglob("*")
        if path.is_file() and path.suffix in STAGES
    )
    if not shader_files:
        print("No shader stages found.", file=sys.stderr)
        return 2

    failures: list[str] = []
    expanded_sources: dict[Path, Path] = {}

    with tempfile.TemporaryDirectory(prefix="aetheris-glsl-") as temp_dir:
        temp_root = Path(temp_dir)

        for shader_path in shader_files:
            try:
                expanded = expand_includes(
                    shader_path.read_text(encoding="utf-8"),
                    (shader_path.resolve(),),
                )
                stage = STAGES[shader_path.suffix]
                temp_path = temp_root / f"{shader_path.stem}.{stage}"
                temp_path.write_text(expanded, encoding="utf-8")
                expanded_sources[shader_path] = temp_path
            except (OSError, ValueError) as exc:
                failures.append(f"{shader_path.relative_to(ROOT)}: {exc}")

        variants = [
            ("default", []),
            ("LabPBR", ["--define-macro", "MC_TEXTURE_FORMAT_LAB_PBR=1"]),
        ]

        for variant_name, defines in variants:
            for shader_path, temp_path in expanded_sources.items():
                result = run_validator([
                    "glslangValidator", *defines,
                    "-S", STAGES[shader_path.suffix], str(temp_path)
                ])
                if result.returncode != 0:
                    failures.append(
                        f"[{variant_name}] {shader_path.relative_to(ROOT)}:\n"
                        f"{result.stdout}{result.stderr}"
                    )
                else:
                    print(f"PASS [{variant_name}] {shader_path.relative_to(ROOT)}")

            for vertex_path in (p for p in shader_files if p.suffix == ".vsh"):
                fragment_path = vertex_path.with_suffix(".fsh")
                if fragment_path not in expanded_sources:
                    failures.append(f"Missing fragment stage for {vertex_path.relative_to(ROOT)}")
                    continue

                result = run_validator([
                    "glslangValidator", *defines, "-l",
                    str(expanded_sources[vertex_path]),
                    str(expanded_sources[fragment_path]),
                ])
                if result.returncode != 0:
                    failures.append(
                        f"[{variant_name}] link {vertex_path.stem}:\n"
                        f"{result.stdout}{result.stderr}"
                    )
                else:
                    print(f"LINK PASS [{variant_name}] {vertex_path.stem}")

    if failures:
        print("\n\n".join(failures), file=sys.stderr)
        return 1

    print(f"Validated and linked {len(shader_files)} GLSL stages in {len(variants)} variants.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

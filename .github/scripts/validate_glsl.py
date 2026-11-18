#!/usr/bin/env python3
"""Expand Iris includes, compile GLSL stages, and link stage pairs in both PBR modes."""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHADERS = ROOT / "shaders"
INCLUDE_RE = re.compile(r'^\s*#include\s+"([^"]+)"\s*$', re.MULTILINE)
VERSION_RE = re.compile(r"^(#version[^\n]*\n)", re.MULTILINE)
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


def with_iris_defines(source: str, labpbr: bool) -> str:
    definitions = ""
    if labpbr:
        definitions += "#define MC_TEXTURE_FORMAT_LAB_PBR 1\n"
    result, count = VERSION_RE.subn(r"\1" + definitions, source, count=1)
    if count != 1:
        raise ValueError("Missing #version directive")
    return result


def validate_water_pipeline() -> list[str]:
    """Check the cross-pass contract that GLSL compilation alone cannot prove."""
    failures: list[str] = []

    try:
        water_vertex = (SHADERS / "gbuffers_water.vsh").read_text(encoding="utf-8")
        water_fragment = (SHADERS / "gbuffers_water.fsh").read_text(encoding="utf-8")
        water_composite = (SHADERS / "composite.fsh").read_text(encoding="utf-8")
        target_formats = (SHADERS / "lib" / "lighting.glsl").read_text(encoding="utf-8")
        properties = (ROOT / "shaders.properties").read_text(encoding="utf-8")
    except OSError as exc:
        return [f"Could not inspect the water pipeline: {exc}"]

    required = [
        ("Vitrail fluid flag is forwarded from mc_Entity.y",
         "vIsFluid = mc_Entity.y;" in water_vertex),
        ("Water vertex and fragment stages both use the fluid flag",
         "vIsFluid > 0.5" in water_vertex and "vIsFluid > 0.5" in water_fragment),
        ("Water writes the normal and surface-colour buffers",
         "RENDERTARGETS: 0,2,3" in water_fragment
         and "gl_FragData[1]" in water_fragment
         and "gl_FragData[2]" in water_fragment),
        ("Water normal and surface-colour targets have formats",
         "colortex2Format" in target_formats and "colortex3Format" in target_formats),
        ("Water composite reads both dedicated targets",
         "texture2D(colortex2" in water_composite
         and "texture2D(colortex3" in water_composite),
        ("Independent water target blending is configured",
         "blend.gbuffers_water.colortex2" in properties
         and "blend.gbuffers_water.colortex3" in properties),
    ]

    for label, passed in required:
        if passed:
            print(f"PASS [water pipeline] {label}")
        else:
            failures.append(f"Water pipeline validation failed: {label}")

    return failures


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

    try:
        expanded = {
            path: expand_includes(path.read_text(encoding="utf-8"), (path.resolve(),))
            for path in shader_files
        }
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1

    failures: list[str] = validate_water_pipeline()
    variants = [("default", False), ("LabPBR", True)]

    with tempfile.TemporaryDirectory(prefix="aetheris-glsl-") as temp_dir:
        temp_root = Path(temp_dir)

        for variant_name, labpbr in variants:
            compiled_paths: dict[Path, Path] = {}

            for shader_path, source in expanded.items():
                try:
                    source = with_iris_defines(source, labpbr)
                except ValueError as exc:
                    failures.append(f"{shader_path.relative_to(ROOT)}: {exc}")
                    continue

                stage = STAGES[shader_path.suffix]
                temp_path = temp_root / f"{variant_name}_{shader_path.stem}.{stage}"
                temp_path.write_text(source, encoding="utf-8")
                compiled_paths[shader_path] = temp_path

                result = run_validator(["glslangValidator", "-S", stage, str(temp_path)])
                if result.returncode != 0:
                    failures.append(
                        f"[{variant_name}] {shader_path.relative_to(ROOT)}:\n"
                        f"{result.stdout}{result.stderr}"
                    )
                else:
                    print(f"PASS [{variant_name}] {shader_path.relative_to(ROOT)}")

            for vertex_path in (p for p in shader_files if p.suffix == ".vsh"):
                fragment_path = vertex_path.with_suffix(".fsh")
                if vertex_path not in compiled_paths or fragment_path not in compiled_paths:
                    failures.append(f"Missing vertex/fragment pair for {vertex_path.relative_to(ROOT)}")
                    continue

                result = run_validator([
                    "glslangValidator", "-l",
                    str(compiled_paths[vertex_path]), str(compiled_paths[fragment_path])
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

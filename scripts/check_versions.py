#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 Florian Obersteiner
# SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
# SPDX-FileComment: assisted-by Qwen3.5 397B A17B

#
# SPDX-License-Identifier: Unlicense

"""
Version consistency checker.

Verifies that version numbers are consistent across:
- build.zig (zdt_version, tzdb_release, minimum_zig_version)
- build.zig.zon (version, minimum_zig_version_zon)
- lib/tzdata.zig (tzdb_version)
- README.md (tzdata badge)
- CHANGELOG.md (latest version heading)

Exits with code 1 on any inconsistency.
"""

import re
import sys
from pathlib import Path


def extract_zig_version(content: str, var_name: str) -> tuple[str, int] | None:
    """Extract a SemanticVersion struct from Zig source code."""
    pattern = rf"const\s+{var_name}\s*=\s*std\.SemanticVersion\s*\{{\s*\.major\s*=\s*(\d+),\s*\.minor\s*=\s*(\d+),\s*\.patch\s*=\s*(\d+)\s*\}}"
    match = re.search(pattern, content)
    if match:
        major, minor, patch = match.groups()
        line_num = content[: match.start()].count("\n") + 1
        return f"{major}.{minor}.{patch}", line_num
    return None


def extract_zig_string(content: str, var_name: str) -> tuple[str, int] | None:
    """Extract a string constant from Zig source code."""
    pattern = rf'const\s+{var_name}\s*=\s*"([^"]+)"'
    match = re.search(pattern, content)
    if match:
        line_num = content[: match.start()].count("\n") + 1
        return match.group(1), line_num
    return None


def extract_zon_version(content: str) -> tuple[str, int] | None:
    """Extract version from build.zig.zon file."""
    pattern = r'\.version\s*=\s*"([^"]+)"'
    match = re.search(pattern, content)
    if match:
        line_num = content[: match.start()].count("\n") + 1
        return match.group(1), line_num
    return None


def extract_zon_minimum_zig_version(content: str) -> tuple[str, int] | None:
    """Extract minimum_zig_version from build.zig.zon file."""
    pattern = r'\.minimum_zig_version\s*=\s*"([^"]+)"'
    match = re.search(pattern, content)
    if match:
        line_num = content[: match.start()].count("\n") + 1
        return match.group(1), line_num
    return None


def extract_readme_tzdb_badge(content: str) -> tuple[str, int] | None:
    """Extract tzdb version from README.md badge."""
    pattern = r"img\.shields\.io/badge/tzdata-([a-zA-Z0-9]+)"
    match = re.search(pattern, content)
    if match:
        line_num = content[: match.start()].count("\n") + 1
        return match.group(1), line_num
    return None


def extract_changelog_version(content: str) -> tuple[str, int] | None:
    """Extract latest version from CHANGELOG.md (first non-Unreleased heading)."""
    # Match patterns like: ## 2026-04-23, v0.9.3
    pattern = r"^##\s+\d{4}-\d{2}-\d{2},\s+v(\d+\.\d+\.\d+)"
    match = re.search(pattern, content, re.MULTILINE)
    if match:
        line_num = content[: match.start()].count("\n") + 1
        return match.group(1), line_num
    return None


def check_versions(project_root: Path) -> tuple[dict, list[str]]:
    """Check version consistency across all relevant files."""
    versions: dict = {}
    errors: list[str] = []

    # Check build.zig
    build_zig_path = project_root / "build.zig"
    if build_zig_path.exists():
        content = build_zig_path.read_text()

        result = extract_zig_version(content, "zdt_version")
        if result:
            versions["zdt_version"] = {
                "value": result[0],
                "line": result[1],
                "file": "build.zig",
            }
        else:
            errors.append("Could not find zdt_version in build.zig")

        result = extract_zig_string(content, "tzdb_release")
        if result:
            versions["tzdb_release"] = {
                "value": result[0],
                "line": result[1],
                "file": "build.zig",
            }
        else:
            errors.append("Could not find tzdb_release in build.zig")

        result = extract_zig_string(content, "minimum_zig_version")
        if result:
            versions["minimum_zig_version"] = {
                "value": result[0],
                "line": result[1],
                "file": "build.zig",
            }
        else:
            errors.append("Could not find minimum_zig_version in build.zig")
    else:
        errors.append(f"File not found: {build_zig_path}")

    # Check build.zig.zon
    build_zig_zon_path = project_root / "build.zig.zon"
    if build_zig_zon_path.exists():
        content = build_zig_zon_path.read_text()
        result = extract_zon_version(content)
        if result:
            versions["build.zig.zon"] = {
                "value": result[0],
                "line": result[1],
                "file": "build.zig.zon",
            }
        else:
            errors.append("Could not find version in build.zig.zon")

        result = extract_zon_minimum_zig_version(content)
        if result:
            versions["minimum_zig_version_zon"] = {
                "value": result[0],
                "line": result[1],
                "file": "build.zig.zon",
            }
        else:
            errors.append("Could not find minimum_zig_version in build.zig.zon")
    else:
        errors.append(f"File not found: {build_zig_zon_path}")

    # Check lib/tzdata.zig
    tzdata_zig_path = project_root / "lib" / "tzdata.zig"
    if tzdata_zig_path.exists():
        content = tzdata_zig_path.read_text()
        result = extract_zig_string(content, "tzdb_version")
        if result:
            versions["tzdb_version"] = {
                "value": result[0],
                "line": result[1],
                "file": "lib/tzdata.zig",
            }
        else:
            errors.append("Could not find tzdb_version in lib/tzdata.zig")
    else:
        errors.append(f"File not found: {tzdata_zig_path}")

    # Check README.md
    readme_path = project_root / "README.md"
    if readme_path.exists():
        content = readme_path.read_text()
        result = extract_readme_tzdb_badge(content)
        if result:
            versions["readme_badge"] = {
                "value": result[0],
                "line": result[1],
                "file": "README.md",
            }
        else:
            errors.append("Could not find tzdata badge in README.md")
    else:
        errors.append(f"File not found: {readme_path}")

    # Check CHANGELOG.md
    changelog_path = project_root / "CHANGELOG.md"
    if changelog_path.exists():
        content = changelog_path.read_text()
        result = extract_changelog_version(content)
        if result:
            versions["changelog"] = {
                "value": result[0],
                "line": result[1],
                "file": "CHANGELOG.md",
            }
        else:
            errors.append("Could not find version in CHANGELOG.md")
    else:
        errors.append(f"File not found: {changelog_path}")

    # Validate project version consistency
    project_versions = [
        k for k in ("zdt_version", "build.zig.zon", "changelog") if k in versions
    ]
    if len(project_versions) >= 2:
        unique_values = set(versions[k]["value"] for k in project_versions)
        if len(unique_values) > 1:
            error_msg = "Project version inconsistency detected:\n"
            for k in project_versions:
                v = versions[k]
                error_msg += f"  - {v['file']} (line {v['line']}): {v['value']}\n"
            errors.append(error_msg.rstrip())

    # Validate TZDB version consistency
    tzdb_versions = [
        k for k in ("tzdb_release", "tzdb_version", "readme_badge") if k in versions
    ]
    if len(tzdb_versions) >= 2:
        unique_values = set(versions[k]["value"] for k in tzdb_versions)
        if len(unique_values) > 1:
            error_msg = "TZDB version inconsistency detected:\n"
            for k in tzdb_versions:
                v = versions[k]
                error_msg += f"  - {v['file']} (line {v['line']}): {v['value']}\n"
            errors.append(error_msg.rstrip())

    # Validate minimum Zig version consistency
    zig_versions = [
        k for k in ("minimum_zig_version", "minimum_zig_version_zon") if k in versions
    ]
    if len(zig_versions) == 2:
        if versions[zig_versions[0]]["value"] != versions[zig_versions[1]]["value"]:
            error_msg = "Minimum Zig version inconsistency detected:\n"
            for k in zig_versions:
                v = versions[k]
                error_msg += f"  - {v['file']} (line {v['line']}): {v['value']}\n"
            errors.append(error_msg.rstrip())

    return versions, errors


def main() -> int:
    """Main entry point."""
    project_root = Path(__file__).parent.parent

    print("=" * 70)
    print("ZDT Version Consistency Check")
    print("=" * 70)
    print()

    versions, errors = check_versions(project_root)

    # Report found versions with aligned columns
    print("Found versions:")
    print("-" * 70)

    if versions:
        # Calculate column widths dynamically
        file_width = max(len(v["file"]) for v in versions.values())
        key_width = max(len(k) for k in versions.keys())
        value_width = max(len(v["value"]) for v in versions.values())

        # Print header
        print(
            f"  {'File':<{file_width}}  {'Key':<{key_width}}  {'Version':<{value_width}}  Line"
        )
        print(f"  {'-' * file_width}  {'-' * key_width}  {'-' * value_width}  ----")

        # Print each version entry
        for key, v in versions.items():
            print(
                f"  {v['file']:<{file_width}}  {key:<{key_width}}  {v['value']:<{value_width}}  {v['line']}"
            )
    print()

    # Report errors
    if errors:
        print("❌ ERRORS DETECTED:")
        print("-" * 70)
        for error in errors:
            print(error)
            print()
        print("=" * 70)
        print("Release check FAILED. Please fix version inconsistencies.")
        print("=" * 70)
        return 1
    else:
        print("✅ All versions are consistent!")
        print()
        project_ver = versions.get("zdt_version", {}).get("value", "N/A")
        tzdb_ver = versions.get("tzdb_release", {}).get("value", "N/A")
        zig_ver = versions.get("minimum_zig_version", {}).get("value", "N/A")
        print("Summary:")
        print(f"  Project version:   {project_ver}")
        print(f"  TZDB version:      {tzdb_ver}")
        print(f"  Min Zig version:   {zig_ver}")

        return 0


if __name__ == "__main__":
    sys.exit(main())

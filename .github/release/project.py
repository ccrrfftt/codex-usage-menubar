"""Project-specific inputs for the GitHub Release workflow."""
import argparse
import hashlib
import platform
import plistlib
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def version_info(revision):
    script = subprocess.check_output(
        ["git", "show", "--end-of-options", f"{revision}:script/build_and_run.sh"], cwd=ROOT
    )
    embedded = re.findall(rb"<\?xml\b.*?</plist>", script, re.S)
    if len(embedded) != 1:
        raise SystemExit("Expected one embedded Info.plist in script/build_and_run.sh")
    info = plistlib.loads(embedded[0])
    version = info["CFBundleShortVersionString"]
    build = info["CFBundleVersion"]
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) or not build.isdecimal():
        raise SystemExit("Invalid version or build number in Info.plist")
    return version, build


def changelog_section(tag):
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise SystemExit("Expected a vX.Y.Z tag")
    sections = re.split(r"(?m)^## ", (ROOT / "CHANGELOG.md").read_text(encoding="utf-8"))
    for section in sections[1:]:
        heading, _, body = section.partition("\n")
        if re.fullmatch(re.escape(tag[1:]) + r"(?:\s+·.*)?", heading) and body.strip():
            return heading, body.strip()
    raise SystemExit(f"Missing release notes for {tag} in CHANGELOG.md")


def package(output):
    if not output.is_dir() or platform.machine() != "arm64":
        raise SystemExit("Packaging requires an existing output folder and an Apple Silicon Mac")
    version, build = version_info("HEAD")
    subprocess.run(["./script/package.sh"], cwd=ROOT, check=True)
    dist = ROOT / "dist"
    archive = dist / f"Codex-Usage-{version}-macOS-arm64.zip"
    checksums = dist / "SHA256SUMS.txt"
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if checksums.read_text().strip() != f"{digest}  {archive.name}":
        raise SystemExit("Packaged archive failed the SHA-256 check")
    with tempfile.TemporaryDirectory() as unpacked:
        subprocess.run(["ditto", "-x", "-k", archive, unpacked], check=True)
        app = Path(unpacked) / "Codex Usage.app"
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        if (info["CFBundleShortVersionString"], info["CFBundleVersion"]) != (version, build):
            raise SystemExit("Packaged version does not match the release commit")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", app], check=True)
        binary = app / "Contents/MacOS/CodexUsage"
        subprocess.run(["lipo", binary, "-verify_arch", "arm64"], check=True)
    shutil.copy2(archive, output)
    shutil.copy2(checksums, output)


def main():
    commands = argparse.ArgumentParser()
    actions = commands.add_subparsers(dest="action", required=True)
    actions.add_parser("version").add_argument("revision")
    actions.add_parser("check")
    actions.add_parser("package").add_argument("output", type=Path)
    for name in ["notes", "prerelease"]:
        actions.add_parser(name).add_argument("tag")
    args = commands.parse_args()
    if args.action == "version":
        print("v" + version_info(args.revision)[0])
    elif args.action == "check":
        subprocess.run(["./script/check.sh"], cwd=ROOT, check=True)
    elif args.action == "package":
        package(args.output)
    else:
        heading, body = changelog_section(args.tag)
        if args.action == "prerelease":
            print("true" if "预发布" in heading else "false")
        else:
            print(body)
            print("\n适用于 Apple Silicon、macOS 14 及以上。退出旧版后解压 ZIP，替换应用。"
                  "安装包使用本地签名，尚未经过 Apple 公证。")


if __name__ == "__main__":
    main()

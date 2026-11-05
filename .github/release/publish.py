"""Publish a verified build from a versioned commit to this repository's GitHub Releases."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


TAG = re.compile(r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?", re.ASCII)
COMMIT = re.compile(r"[0-9a-f]{40}")


def api(path, method="GET", data=None, *, optional=False):
    command = ["gh", "api", f"repos/{os.environ['GITHUB_REPOSITORY']}/{path}", "--method", method]
    if data is not None:
        command += ["--input", "-"]
    result = subprocess.run(command, input=json.dumps(data) if data is not None else None,
                            capture_output=True, text=True)
    if result.returncode:
        if optional and "(HTTP 404)" in result.stderr:
            return None
        raise RuntimeError(f"GitHub {method} {path} failed: {result.stderr.strip()}")
    return json.loads(result.stdout) if result.stdout.strip() else None


def hash_file(handle):
    digest = hashlib.sha256()
    for block in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(block)
    return "sha256:" + digest.hexdigest()


def local_assets(directory):
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError("Expected a release assets directory")
    assets = {}
    for file in sorted(directory.iterdir()):
        if (file.is_symlink() or not file.is_file() or
                not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", file.name)):
            raise ValueError(f"Unsafe asset path: {file.name!r}")
        with file.open("rb") as handle:
            assets[file.name] = hash_file(handle)
    for manifest in {"SHA256SUMS", "SHA256SUMS.txt"} & assets.keys():
        listed = {}
        for line in (directory / manifest).read_text().splitlines():
            match = re.fullmatch(r"([a-fA-F0-9]{64}) [ *]([^/]+)", line)
            if not match or match[2] in listed:
                raise ValueError(f"Invalid checksum entry in {manifest}")
            listed[match[2]] = "sha256:" + match[1].lower()
        if listed != {name: value for name, value in assets.items() if name != manifest}:
            raise ValueError(f"{manifest} does not match the release assets")
    return assets


def tag_commit(tag):
    ref = api(f"git/ref/tags/{tag}", optional=True)
    if not ref:
        return None
    obj = ref["object"]
    while obj["type"] == "tag":
        obj = api(f"git/tags/{obj['sha']}")["object"]
    if obj["type"] != "commit":
        raise ValueError(f"{tag} does not reference a commit")
    return obj["sha"]


def ensure_tag(tag, commit):
    current = tag_commit(tag)
    if current is None:
        annotated = api("git/tags", "POST", {
            "tag": tag, "message": f"Release {tag}", "type": "commit", "object": commit,
            "tagger": {"name": "github-actions[bot]",
                       "email": "41898282+github-actions[bot]@users.noreply.github.com"},
        })
        # Creating a ref fails if another writer created it first. Never update a ref.
        api("git/refs", "POST", {"ref": f"refs/tags/{tag}", "sha": annotated["sha"]})
        current = tag_commit(tag)
    if current != commit:
        raise ValueError(f"{tag} references {current}, expected {commit}")


def find_release(tag):
    release = api(f"releases/tags/{tag}", optional=True)
    if release:
        return release
    # Releases by tag can omit drafts. Search all pages so an interrupted run resumes.
    page = 1
    while True:
        releases = api(f"releases?per_page=100&page={page}")
        matches = [item for item in releases if item["tag_name"] == tag]
        if len(matches) > 1:
            raise ValueError(f"Multiple releases have tag {tag}")
        if matches:
            return matches[0]
        if len(releases) < 100:
            return None
        page += 1


def check_release(release, tag, commit, notes, prerelease):
    body = (release["body"] or "").replace("\r\n", "\n").rstrip("\n")
    if (release["tag_name"] != tag or release["name"] != tag or body != notes or
            release["prerelease"] != prerelease):
        raise ValueError(f"Existing release metadata differs for {tag}")
    target = release["target_commitish"]
    if COMMIT.fullmatch(target) and target != commit:
        raise ValueError(f"Existing release target differs for {tag}")


def download_hash(asset_id):
    endpoint = f"repos/{os.environ['GITHUB_REPOSITORY']}/releases/assets/{asset_id}"
    with tempfile.TemporaryFile() as output:
        subprocess.run(["gh", "api", endpoint, "-H", "Accept: application/octet-stream"],
                       stdout=output, check=True)
        output.seek(0)
        return hash_file(output)


def remote_assets(release, assets, *, require_all, download):
    indexed = {asset["name"]: asset for asset in release["assets"]}
    if len(indexed) != len(release["assets"]) or indexed.keys() - assets.keys():
        raise ValueError("Release contains unexpected or duplicate assets")
    missing = []
    for name, digest in assets.items():
        asset = indexed.get(name)
        if asset is None:
            missing.append(name)
            continue
        if (asset["state"] == "starter" and asset["size"] == 0 and not asset.get("digest")
                and release["draft"] and not require_all):
            # GitHub can leave an empty starter record after a failed upload.
            api(f"releases/assets/{asset['id']}", "DELETE")
            missing.append(name)
            continue
        if asset["state"] != "uploaded" or asset.get("digest") not in {None, digest}:
            raise ValueError(f"Asset differs: {name}")
        if (download or not asset.get("digest")) and download_hash(asset["id"]) != digest:
            raise ValueError(f"Downloaded SHA-256 differs: {name}")
    if missing and require_all:
        raise ValueError(f"Missing assets: {', '.join(missing)}")
    return missing


def latest_setting(tag, prerelease):
    if prerelease:
        return "false"
    latest = api("releases/latest", optional=True)
    if not latest:
        return "true"
    current = TAG.fullmatch(latest["tag_name"])
    incoming = TAG.fullmatch(tag)
    if current and tuple(map(int, incoming.groups())) > tuple(map(int, current.groups())):
        return "true"
    return "false"


def publish(tag, commit, directory, notes, prerelease):
    if not TAG.fullmatch(tag) or not COMMIT.fullmatch(commit) or not notes.strip():
        raise ValueError("Expected a version tag, full commit SHA and nonempty release notes")
    assets = local_assets(directory)
    release = find_release(tag)
    if release:
        check_release(release, tag, commit, notes, prerelease)
    if release and tag_commit(tag) is None:
        raise ValueError(f"Existing release {tag} has no tag ref to verify")
    ensure_tag(tag, commit)
    if not release:
        release = api("releases", "POST", {
            "tag_name": tag, "target_commitish": commit, "name": tag, "body": notes,
            "draft": True, "prerelease": prerelease,
        })
    release_path = f"releases/{release['id']}"
    check_release(release, tag, commit, notes, prerelease)
    if release["draft"]:
        missing = remote_assets(release, assets, require_all=False, download=False)
        for name in missing:
            subprocess.run(["gh", "release", "upload", tag, str(directory / name),
                            "--repo", os.environ["GITHUB_REPOSITORY"]], check=True)
        release = api(release_path)
        if not release["draft"]:
            raise ValueError("Another writer published the release during upload")
        check_release(release, tag, commit, notes, prerelease)
        remote_assets(release, assets, require_all=True, download=True)
        if tag_commit(tag) != commit:
            raise ValueError("Tag changed before publication")
        api(release_path, "PATCH", {"draft": False, "make_latest": latest_setting(tag, prerelease)})
    release = api(release_path)
    check_release(release, tag, commit, notes, prerelease)
    if release["draft"] or not release["published_at"] or tag_commit(tag) != commit:
        raise ValueError("GitHub did not confirm the expected published release and tag")
    remote_assets(release, assets, require_all=True, download=True)
    print(f"Verified {release['html_url']} at {commit}, {len(assets)} assets")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("commit")
    parser.add_argument("assets", type=Path)
    parser.add_argument("notes", type=Path)
    parser.add_argument("prerelease", choices=["true", "false"])
    args = parser.parse_args()
    try:
        publish(args.tag, args.commit, args.assets, args.notes.read_text().rstrip("\n"),
                args.prerelease == "true")
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as exc:
        sys.exit(str(exc))

"""Determine whether this run should test, package, or publish a GitHub Release."""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlencode


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def version(ref):
    tag = run(sys.executable, ".github/release/project.py", "version", ref)
    version_key(tag)
    return tag


def version_key(tag):
    match = re.fullmatch(
        r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?", tag
    )
    if not match:
        raise ValueError(f"Invalid project release tag: {tag!r}")
    major, minor, patch, suffix = match.groups()
    identifiers = []
    for item in (suffix or "").split("."):
        if item.isdigit() and len(item) > 1 and item.startswith("0"):
            raise ValueError(f"Invalid numeric prerelease identifier in {tag}")
        identifiers.append((0, int(item)) if item.isdigit() else (1, item))
    return int(major), int(minor), int(patch), suffix is None, identifiers


def merged_pr(repo, branch, sha):
    # Listing closed PRs by base works on maintenance branches as well as main.
    query = urlencode(dict(state="closed", base=branch, sort="updated", direction="desc", per_page=100))
    for delay in (0, 3, 9):
        if delay:
            time.sleep(delay)
        pages = run("gh", "api", "--paginate", "--slurp", f"repos/{repo}/pulls?{query}")
        for page in json.loads(pages):
            for pr in page:
                if pr["merged_at"] and pr["merge_commit_sha"] == sha and pr["base"]["repo"]["full_name"] == repo:
                    return pr["number"]
    return None


def main():
    event_name = os.environ["GITHUB_EVENT_NAME"]
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    sha = os.environ["GITHUB_SHA"]
    tag = version(sha)
    check = event_name != "push"
    package = event_name == "workflow_dispatch"
    publish = False
    message = f"Verify {tag} without publishing."
    before = None
    if event_name == "pull_request":
        before = event["pull_request"]["base"]["sha"]
    elif event_name == "push" and not event["created"] and not event["deleted"]:
        before = event["before"]
    if before:
        old = version(before)
        if event_name == "pull_request":
            config_files = run("git", "diff", "--name-only", before, sha, "--",
                               ".github/release", ".github/workflows/project-release.yml")
            package = bool(config_files) or old != tag
        elif version_key(tag) > version_key(old):
            number = merged_pr(os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_REF_NAME"], sha)
            if number:
                check = package = publish = True
                message = f"PR #{number} merged: verify and publish {old} → {tag}."
            else:
                message = f"No merged PR matches this push; skip release of {tag}."
        else:
            message = f"No new version ({old} → {tag}); skip release."
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        for key, value in dict(tag=tag, check=check, package=package, publish=publish).items():
            print(f"{key}={str(value).lower() if isinstance(value, bool) else value}", file=output)
    print(message)
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        print(message, file=summary)


if __name__ == "__main__":
    main()

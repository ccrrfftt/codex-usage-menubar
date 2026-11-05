"""Check release attachments and inspect their archives without installing them."""
import hashlib
import io
import posixpath
import re
import stat
import sys
import tarfile
import zipfile
from pathlib import Path, PurePosixPath


# Bounds apply to expanded members too, including archives inside an attachment.
MAX_FILE = 256 * 1024 * 1024
MAX_TOTAL = 2 * 1024**3
MAX_MEMBERS = 100_000
DIGEST = r"[0-9a-fA-F]{64}"
SAMPLES = {".env.example", ".env.sample", ".env.template"}
PRIVATE_FILES = {".git", ".aws", ".ssh", ".netrc", "credentials.json", "id_rsa", "id_ed25519"}
CREDENTIALS = (
    ("private key", rb"-----BEGIN (?:[A-Z0-9 ]* )?PRIVATE KEY-----\s+[A-Za-z0-9+/=\r\n]{40,}"),
    ("access token", rb"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,}|xox[bpoas]-[A-Za-z0-9-]{25,})\b"),
    ("Google API key", rb"\bAIza[0-9A-Za-z_-]{35}\b"),
    ("OpenAI token", rb"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,}\b"),
)
HOME_PATH = re.compile(rb"(?:/(?:Users|home)/|[A-Za-z]:[\\/]+Users[\\/]+)([A-Za-z0-9][A-Za-z0-9_.-]{0,63})[\\/]", re.I)
PUBLIC_HOMES = {b"runner", b"runneradmin", b"vsts", b"shared", b"example", b"user", b"username", b"yourname", b"your-user", b"your-username", b"public", b"test", b"testuser", b"node", b"ubuntu", b"build", b"builder"}
CREDENTIALS = [(label, re.compile(pattern)) for label, pattern in CREDENTIALS]


def check_name(name):
    parts = PurePosixPath(name).parts
    if name.startswith("/") or "\\" in name or re.match(r"^[A-Za-z]:", name) or ".." in parts or any(ord(c) < 32 for c in name):
        raise ValueError("unsafe archive entry name")
    for part in parts:
        word = part.casefold()
        if word in PRIVATE_FILES or (word == ".env" or word.startswith(".env.")) and word not in SAMPLES:
            raise ValueError("private configuration file")
    if name.lower().endswith((".p12", ".pfx", ".mobileprovision", ".provisionprofile")):
        raise ValueError("private signing material")


def check_content(data):
    for label, pattern in CREDENTIALS:
        for match in pattern.finditer(data):
            value = match[0].lower()
            # Documentation and test fixtures sometimes use repeated placeholder characters.
            if label != "private key" and (len(set(value[-24:])) < 5 or re.search(rb"(?:placeholder|dummy|example){2,}", value)):
                continue
            raise ValueError(label)
    if any(m[1].lower() not in PUBLIC_HOMES for m in HOME_PATH.finditer(data)):
        raise ValueError("private home directory path")


def check_link(name, target):
    result = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
    if target.startswith("/") or "\\" in target or result == ".." or result.startswith("../"):
        raise ValueError("unsafe archive link")


class Inspector:
    def __init__(self):
        self.total = 0
        self.members = 0

    def inspect(self, name, size, stream, depth=0):
        check_name(name)
        self.total += size
        self.members += 1
        if size > MAX_FILE or self.total > MAX_TOTAL or self.members > MAX_MEMBERS or depth > 6:
            raise ValueError("archive exceeds inspection limits")
        data = stream.read(size + 1)
        if len(data) != size:
            raise ValueError("archive member size mismatch")
        if name.lower().endswith(".zip") or data.startswith((b"PK\x03\x04", b"PK\x05\x06")):
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                for entry in archive.infolist():
                    try:
                        check_name(entry.filename)
                        if entry.is_dir():
                            continue
                        with archive.open(entry) as member:
                            if stat.S_ISLNK(entry.external_attr >> 16):
                                if entry.file_size > 4096:
                                    raise ValueError("oversized link")
                                check_link(entry.filename, member.read().decode("utf-8"))
                            else:
                                self.inspect(entry.filename, entry.file_size, member, depth + 1)
                    except ValueError as exc:
                        raise ValueError(f"{entry.filename!r}: {exc}") from exc
        elif name.lower().endswith((".tgz", ".tar.gz", ".tar")):
            with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as archive:
                for entry in archive:
                    try:
                        check_name(entry.name)
                        if entry.issym():
                            check_link(entry.name, entry.linkname)
                        elif entry.islnk():
                            check_link("", entry.linkname)
                        elif entry.isfile():
                            with archive.extractfile(entry) as member:
                                self.inspect(entry.name, entry.size, member, depth + 1)
                        elif not entry.isdir():
                            raise ValueError("special file in archive")
                    except ValueError as exc:
                        raise ValueError(f"{entry.name!r}: {exc}") from exc
        else:
            check_content(data)


def manifest(name):
    return name.lower() in {"sha256sums", "sha256sums.txt"} or name.lower().endswith(".sha256")


def check_files(directory):
    entries = sorted(directory.iterdir())
    inspector = Inspector()
    hashes = {}
    manifests = []
    for path in entries:
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"{path.name!r}: expected regular attachment")
        with path.open("rb") as stream:
            try:
                inspector.inspect(path.name, path.stat().st_size, stream)
            except (ValueError, zipfile.BadZipFile, tarfile.TarError, RuntimeError) as exc:
                raise ValueError(f"{path.name!r}: {exc}") from exc
            stream.seek(0)
            if manifest(path.name):
                manifests.append(path)
            else:
                digest = hashlib.sha256()
                for chunk in iter(lambda: stream.read(1 << 20), b""):
                    digest.update(chunk)
                hashes[path.name] = digest.hexdigest()
    covered = set()
    for path in manifests:
        lines = path.read_text(encoding="utf-8").splitlines()
        names = set()
        for line in lines:
            if not line.strip():
                continue
            gnu = re.fullmatch(rf"({DIGEST}) [ *](.+)", line)
            bsd = re.fullmatch(rf"SHA256 \((.+)\) = ({DIGEST})", line)
            if gnu:
                digest, name = gnu.groups()
            elif bsd:
                name, digest = bsd.groups()
            elif path.name.lower().endswith(".sha256") and re.fullmatch(DIGEST, line):
                name, digest = path.name[:-7], line
            else:
                raise ValueError(f"{path.name!r}: invalid SHA-256 entry")
            name = name.removeprefix("./")
            if name in names or hashes.get(name) != digest.lower():
                raise ValueError(f"{path.name!r}: duplicate, missing, or mismatched attachment")
            names.add(name)
        if not names:
            raise ValueError(f"{path.name!r}: empty SHA-256 manifest")
        covered.update(names)
    if covered != hashes.keys():
        raise ValueError(f"missing SHA-256 entries for {sorted(hashes.keys() - covered)}")
    print(f"Verified {len(entries)} attachments and inspected {inspector.members} files including archive contents.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: verify_assets.py ASSET_DIRECTORY")
    try:
        check_files(Path(sys.argv[1]))
    except (OSError, ValueError) as error:
        sys.exit(f"Release attachment verification failed: {error}")

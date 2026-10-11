#!/usr/bin/env python3
"""Export/import macOS defaults without extracting untrusted paths or deleting user folders."""

import argparse
from datetime import datetime
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
import zipfile

MAX_PLIST = 8 * 1024 * 1024
MAX_ARCHIVE = 64 * 1024 * 1024
NAMESPACES = {"apple", "user", "global"}  # 'global' is the legacy name for root's defaults.


def valid_domain(value):
    return value not in {".", ".."} and re.fullmatch(r"[A-Za-z0-9_.-]+", value)


def command(root, *arguments):
    args = (["sudo"] if root else []) + ["defaults", *arguments]
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout


def domains(root):
    values = [value.strip() for value in command(root, "domains").decode().strip().split(",")]
    return [value for value in values if valid_domain(value)]


def read_archive(path):
    """Validate every member and plist before performing any defaults writes."""
    records, seen, total = [], set(), 0
    with zipfile.ZipFile(path) as archive:
        if len(archive.infolist()) > 4096:
            raise ValueError("Too many archive entries")
        for entry in archive.infolist():
            name = PurePosixPath(entry.filename)
            if (name.is_absolute() or ".." in name.parts or "\\" in entry.filename
                    or stat.S_ISLNK(entry.external_attr >> 16)):
                raise ValueError(f"Unsafe archive member: {entry.filename}")
            if entry.is_dir():
                if len(name.parts) != 1 or name.parts[0] not in NAMESPACES:
                    raise ValueError(f"Unexpected directory: {entry.filename}")
                continue
            if (len(name.parts) != 2 or name.parts[0] not in NAMESPACES
                    or name.suffix != ".plist" or not valid_domain(name.stem)):
                raise ValueError(f"Unexpected archive member: {entry.filename}")
            identity = (name.parts[0] == "global", name.stem)
            if identity in seen:
                raise ValueError(f"Duplicate preference domain: {name.stem}")
            seen.add(identity)
            total += entry.file_size
            if entry.file_size > MAX_PLIST or total > MAX_ARCHIVE:
                raise ValueError("Preference archive exceeds size limits")
            with archive.open(entry) as stream:
                content = stream.read(MAX_PLIST + 1)
            if len(content) > MAX_PLIST:
                raise ValueError("Preference file exceeds size limit")
            if not isinstance(plistlib.loads(content), dict):
                raise ValueError(f"Preference domain must contain a dictionary: {name.stem}")
            records.append((identity[0], name.stem, content))
    return records


def export_archive(output, include_root=False):
    output.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation prevents replacing a previous backup or following an output symlink.
    with output.open("xb") as handle:
        output.chmod(0o600)
        try:
            with zipfile.ZipFile(handle, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                for root in ([False, True] if include_root else [False]):
                    for domain in domains(root):
                        content = command(root, "export", domain, "-")
                        plistlib.loads(content)
                        namespace = "global" if root else ("apple" if domain.startswith("com.apple.") else "user")
                        archive.writestr(f"{namespace}/{domain}.plist", content)
        except BaseException:
            output.unlink()
            raise
    print(f"Preferences exported to {output}")


def import_archive(path, include_root=False, backup_parent=None):
    records = [record for record in read_archive(path) if include_root or not record[0]]
    if not records:
        raise ValueError("Archive contains no selected preference domains")
    backup_parent = backup_parent or Path.home() / ".local/state/dotfiles/preferences"
    backup_parent.mkdir(parents=True, exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix="before-import-", dir=backup_parent))
    existing = {root: set(domains(root)) for root in {record[0] for record in records}}
    previous = {}
    # Back up all affected domains before the first write.
    for root, domain, _ in records:
        if domain in existing[root]:
            destination = backup / f"{'root' if root else 'user'}-{domain}.plist"
            destination.write_bytes(command(root, "export", domain, "-"))
            previous[(root, domain)] = destination
        else:
            previous[(root, domain)] = None
    print(f"Previous preferences saved to {backup}", flush=True)
    applied = []
    try:
        with tempfile.TemporaryDirectory(prefix="dotfiles-defaults-") as temporary:
            for root, domain, content in records:
                source = Path(temporary) / "preferences.plist"
                source.write_bytes(content)
                # Include the failing write in rollback in case defaults partially changed it.
                applied.append((root, domain))
                command(root, "import", domain, str(source))
    except BaseException:
        for root, domain in reversed(applied):
            try:
                if previous[(root, domain)] is None:
                    command(root, "delete", domain)
                else:
                    command(root, "import", domain, str(previous[(root, domain)]))
            except subprocess.CalledProcessError as error:
                print(f"Rollback failed for {domain}: {error}. Backup: {backup}", file=sys.stderr)
        raise
    print(f"Imported {len(records)} domains. Restart affected apps to load the changes.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["import", "export"])
    parser.add_argument("archive", nargs="?", type=Path)
    parser.add_argument("--include-root", action="store_true", help="Also handle root's preference domains using sudo")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("This utility requires macOS")
    if args.operation == "import" and args.archive is None:
        parser.error("Import requires a ZIP archive path")
    try:
        if args.operation == "export":
            output = args.archive or Path.home() / f"defaults-{datetime.now():%Y%m%d-%H%M%S-%f}.zip"
            export_archive(output.expanduser(), args.include_root)
        else:
            import_archive(args.archive.expanduser(), args.include_root)
    except (OSError, ValueError, zipfile.BadZipFile, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Error: {error}\n")


if __name__ == "__main__":
    main()

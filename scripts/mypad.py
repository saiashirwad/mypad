#!/usr/bin/env python3
"""Place PNG references, capture the current iPad view, and back up editable boards."""
import argparse
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import time
import uuid
import zipfile

REMOTE = "Documents/AgentBridgePrototype"
BUNDLE = "in.texoport.mypad"
CONFIG = Path.home() / ".config/mypad/config.json"
EXPORTS = Path.home() / "Library/Application Support/MyPad/exports"
LIMIT = 512 * 1024 * 1024


class Failure(Exception):
    def __init__(self, code, message):
        self.code = code
        super().__init__(message)


def copy(device, direction, source, destination, check=True):
    try:
        result = subprocess.run([
            "xcrun", "devicectl", "device", "copy", direction,
            "--source", str(source), "--destination", str(destination), "--device", device,
            "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE, "--quiet"
        ], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired) as error:
        if not check:
            return False
        raise Failure("device_unavailable", str(error)) from error
    if result.returncode and check:
        raise Failure("device_unavailable", (result.stderr + result.stdout).strip())
    return result.returncode == 0


def make_command(kind):
    return dict(id=str(uuid.uuid4()), kind=kind, title="Reference", x=0, y=0,
                width=0, height=0, expiresAt=time.time() + 30)


def publish(device, command, folder):
    command["expiresAt"] = time.time() + 30
    path = folder / (command["id"] + ".json")
    path.write_text(json.dumps(command, allow_nan=False))
    copy(device, "to", path, f"{REMOTE}/inbox/{path.name}")
    ack = folder / "ack.json"
    deadline = time.monotonic() + 35
    while time.monotonic() < deadline:
        if copy(device, "from", f"{REMOTE}/outbox/ack-{command['id']}.json", ack, check=False):
            receipt = json.loads(ack.read_text())
            if receipt.get("id") != command["id"]:
                raise Failure("invalid_receipt", "Received an unrelated command receipt")
            if receipt["status"] != "ok":
                raise Failure(receipt.get("code", "app_error"), receipt["message"])
            return receipt
        time.sleep(0.3)
    raise Failure("unknown_outcome", f"No acknowledgement. Keep MyPad open and the iPad unlocked. "
                  f"Command {command['id']} may already have applied; check status/capture before another mutation.")


def png_size(path):
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise Failure("invalid_input", "Use a PNG image; render other formats on the Mac first")
    width, height = struct.unpack(">II", header[16:24])
    if not width or not height or width * height > 20_000_000 or path.stat().st_size > 100 * 1024 * 1024:
        raise Failure("invalid_input", "PNG exceeds the supported image size")
    return width, height


def validate_package(folder):
    manifest = json.loads((folder / "manifest.json").read_text())
    if (manifest.get("format") != "mypad-board" or manifest.get("version") != 1
            or manifest.get("inkFile") != "ink.drawing" or manifest.get("previewFile") != "preview.png"
            or manifest.get("boardSize") != {"width": 3000, "height": 3000}):
        raise Failure("invalid_backup", "Unsupported backup format")
    view = manifest["view"]
    if not all(isinstance(view[k], (int, float)) and math.isfinite(view[k]) for k in ("centerX", "centerY", "zoomScale")) or not 0.25 <= view["zoomScale"] <= 4:
        raise Failure("invalid_backup", "Invalid saved view")
    refs = manifest["references"]
    if not isinstance(refs, list) or len(refs) > 64:
        raise Failure("invalid_backup", "Invalid reference list")
    files = {"manifest.json", "ink.drawing", "preview.png"}
    ids = set()
    for ref in refs:
        identifier = ref["id"]
        if str(uuid.UUID(identifier)) != identifier or identifier in ids or ref["file"] != f"assets/{identifier}.png":
            raise Failure("invalid_backup", "Invalid reference identity or path")
        ids.add(identifier)
        frame = ref["frame"]
        x, y, w, h = (frame[k] for k in ("x", "y", "width", "height"))
        if not all(isinstance(v, (int, float)) and math.isfinite(v) for v in (x, y, w, h)) or min(x, y) < 0 or min(w, h) < 10 or x+w > 3000 or y+h > 3000:
            raise Failure("invalid_backup", "Invalid reference frame")
        png_size(folder / ref["file"])
        files.add(ref["file"])
    if (folder / "ink.drawing").stat().st_size > 100 * 1024 * 1024:
        raise Failure("invalid_backup", "Ink exceeds supported size")
    png_size(folder / "preview.png")
    if sum((folder / name).stat().st_size for name in files) > LIMIT:
        raise Failure("invalid_backup", "Backup exceeds supported size")
    return manifest, files


def unpack(archive, folder):
    with zipfile.ZipFile(archive) as zipped:
        infos = zipped.infolist()
        if len(infos) > 67 or sum(i.file_size for i in infos) > LIMIT:
            raise Failure("invalid_backup", "Archive exceeds supported size")
        names = set()
        for info in infos:
            name = info.filename
            allowed = name in {"manifest.json", "ink.drawing", "preview.png"}
            if name.startswith("assets/") and name.endswith(".png"):
                try:
                    identifier = name[7:-4]
                    allowed = str(uuid.UUID(identifier)) == identifier
                except ValueError:
                    allowed = False
            if not allowed or name in names or (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise Failure("invalid_backup", "Unexpected or duplicate archive entry")
            names.add(name)
            destination = folder / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            with zipped.open(info) as source, destination.open("xb") as target:
                import shutil
                shutil.copyfileobj(source, target)
        manifest, required = validate_package(folder)
        if names != required:
            raise Failure("invalid_backup", "Archive entries do not match its manifest")
        return manifest, required


def result(operation, receipt, **extra):
    return dict(ok=True, operation=operation, commandId=receipt["id"], revision=receipt["revision"], **extra)


def run(args):
    if args.action == "configure":
        CONFIG.parent.mkdir(parents=True, exist_ok=True)
        temporary = CONFIG.with_suffix(".tmp")
        temporary.write_text(json.dumps({"device": args.device_id}))
        temporary.replace(CONFIG)
        return dict(ok=True, operation="configure", device=args.device_id, config=str(CONFIG))
    device = args.device or os.environ.get("MYPAD_DEVICE_ID")
    if not device:
        if not CONFIG.exists():
            raise Failure("config_missing", "Run mypad configure --device DEVICE_ID once")
        device = json.loads(CONFIG.read_text())["device"]
    command = make_command(args.action)
    with tempfile.TemporaryDirectory(prefix="mypad-") as temporary:
        folder = Path(temporary)
        if args.action == "status" and args.command_id:
            identifier = str(uuid.UUID(args.command_id))
            ack = folder / "ack.json"
            if not copy(device, "from", f"{REMOTE}/outbox/ack-{identifier}.json", ack, check=False):
                raise Failure("unresolved_command", "No receipt available for that command; keep the app open and check again")
            receipt = json.loads(ack.read_text())
            if receipt.get("id") != identifier:
                raise Failure("invalid_receipt", "Command receipt identity mismatch")
            return dict(ok=True, operation="status", commandId=identifier, receipt=receipt)
        if args.action == "put":
            source = args.file.expanduser().resolve()
            w, h = png_size(source)
            command.update(kind="image", title=args.title or source.stem, imageFile=f"upload-{command['id']}.png")
            if any(v is not None for v in (args.x, args.y, args.width, args.height)):
                width = args.width if args.width is not None else (args.height * w / h if args.height is not None else min(w, 1100))
                height = args.height if args.height is not None else width * h / w
                x, y = args.x or 0, args.y or 0
                if not all(math.isfinite(v) for v in (x, y, width, height)) or min(x, y) < 0 or min(width, height) < 10 or x+width > 3000 or y+height > 3000:
                    raise Failure("invalid_input", "Reference must fit the 3000 × 3000 board")
                command.update(x=x, y=y, width=width, height=height)
            copy(device, "to", source, f"{REMOTE}/assets/{command['imageFile']}")
        elif args.action in ("clear", "restore"):
            command["expectedRevision"] = args.if_revision
        if args.action == "restore":
            _, files = unpack(args.file.expanduser().resolve(), folder)
            command["restoreFolder"] = command["id"]
            copy(device, "to", folder, f"{REMOTE}/restore/{command['id']}")
        if args.action == "backup":
            output = args.output.expanduser().resolve()
            if output.exists():
                raise Failure("output_exists", "Choose a new backup path; existing files are preserved")
        receipt = publish(device, command, folder)
        if args.action == "capture":
            output = (args.output or EXPORTS / command["id"]).expanduser().resolve()
            output.mkdir(parents=True, exist_ok=True)
            name = f"snapshot-{command['id']}.json"
            copy(device, "from", f"{REMOTE}/outbox/{name}", folder / name)
            snapshot = json.loads((folder / name).read_text())
            if snapshot["id"] != command["id"] or snapshot["imageFile"] != f"snapshot-{command['id']}.png" or snapshot["inkFile"] != f"ink-{command['id']}.drawing":
                raise Failure("invalid_capture", "Capture identity mismatch")
            for key in ("imageFile", "inkFile"):
                copy(device, "from", f"{REMOTE}/outbox/{snapshot[key]}", output / snapshot[key])
            (output / name).write_text(json.dumps(snapshot, indent=2))
            return result(args.action, receipt, image=str(output / snapshot["imageFile"]), metadata=str(output / name), snapshot=snapshot)
        if args.action == "backup":
            name = f"backup-{command['id']}"
            if receipt.get("backupFolder") != name:
                raise Failure("invalid_backup", "Backup identity mismatch")
            remote = f"{REMOTE}/outbox/{name}"
            copy(device, "from", f"{remote}/manifest.json", folder / "manifest.json")
            manifest = json.loads((folder / "manifest.json").read_text())
            # Validate paths before allowing them into a transfer destination.
            paths = ["ink.drawing", "preview.png"]
            for ref in manifest["references"]:
                identifier = str(uuid.UUID(ref["id"]))
                if ref["file"] != f"assets/{identifier}.png":
                    raise Failure("invalid_backup", "Invalid remote asset path")
                paths.append(ref["file"])
            for path in paths:
                (folder / path).parent.mkdir(parents=True, exist_ok=True)
                copy(device, "from", f"{remote}/{path}", folder / path)
            _, files = validate_package(folder)
            output.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=output.parent, suffix=".mypad", delete=False) as staged:
                stage = Path(staged.name)
            try:
                with zipfile.ZipFile(stage, "w", zipfile.ZIP_DEFLATED) as zipped:
                    for path in sorted(files):
                        zipped.write(folder / path, path)
                # Atomic no-overwrite publication, even if another process used the path meanwhile.
                os.link(stage, output)
            finally:
                stage.unlink(missing_ok=True)
            return result(args.action, receipt, backup=str(output))
        return result(args.action, receipt, message=receipt["message"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", help="Override the configured paired iPad")
    sub = parser.add_subparsers(dest="action", required=True)
    config = sub.add_parser("configure")
    config.add_argument("--device", dest="device_id", required=True)
    status = sub.add_parser("status")
    status.add_argument("--command-id", help="Inspect the receipt of a previously timed-out command")
    put = sub.add_parser("put")
    put.add_argument("file", type=Path)
    put.add_argument("--title")
    for key in ("x", "y", "width", "height"):
        put.add_argument("--"+key, type=float)
    capture = sub.add_parser("capture")
    capture.add_argument("--output", type=Path)
    backup = sub.add_parser("backup")
    backup.add_argument("--output", type=Path, required=True)
    clear = sub.add_parser("clear")
    clear.add_argument("--if-revision", type=int, required=True)
    restore = sub.add_parser("restore")
    restore.add_argument("file", type=Path)
    restore.add_argument("--if-revision", type=int, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(run(args), indent=2, allow_nan=False))
    except (Failure, OSError, ValueError, KeyError, TypeError, RuntimeError, zipfile.BadZipFile) as error:
        print(json.dumps(dict(ok=False, code=getattr(error, "code", "invalid_input"), message=str(error))), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

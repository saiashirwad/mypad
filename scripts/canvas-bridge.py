#!/usr/bin/env python3
"""PROTOTYPE: agent ↔ iPad file mailbox using Xcode's paired-device transport."""
import argparse
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
REMOTE = "Documents/AgentBridgePrototype"
BUNDLE = "in.texoport.mypad"


def device_command(device, *args, check=True):
    result = subprocess.run(
        ["xcrun", "devicectl", "device", *args, "--device", device,
         "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE, "--quiet"],
        capture_output=True, text=True, timeout=30,
    )
    if check and result.returncode:
        raise RuntimeError((result.stderr + result.stdout).strip())
    return result


def put(device, source, destination):
    device_command(device, "copy", "to", "--source", str(source), "--destination", destination)


def get(device, source, destination, check=True):
    return device_command(device, "copy", "from", "--source", source, "--destination", str(destination), check=check)


def publish(device, command, folder):
    # Publish the command after its assets. The app ignores incomplete JSON
    # until the transfer has produced a fully decodable command.
    path = folder / f"{command['id']}.json"
    path.write_text(json.dumps(command))
    put(device, path, f"{REMOTE}/inbox/{path.name}")
    ack = folder / "ack.json"
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        result = get(device, f"{REMOTE}/outbox/ack-{command['id']}.json", ack, check=False)
        if result.returncode == 0 and ack.exists():
            receipt = json.loads(ack.read_text())
            if receipt["status"] != "ok":
                raise RuntimeError(receipt["message"])
            return receipt
        time.sleep(0.5)
    raise RuntimeError("No iPad acknowledgement within 20 seconds. Keep MyPad open and the iPad unlocked. The command remains queued.")


def command_base(kind):
    return dict(id=str(uuid.uuid4()), kind=kind, title="Canvas snapshot", x=0, y=0, width=0, height=0)


def pull_latest(device, output, metadata_name="latest.json"):
    output.mkdir(parents=True, exist_ok=True)
    metadata = output / metadata_name
    get(device, f"{REMOTE}/outbox/{metadata_name}", metadata)
    snapshot = json.loads(metadata.read_text())
    for key in ("imageFile", "inkFile"):
        name = snapshot[key]
        if Path(name).name != name:
            raise RuntimeError("Invalid snapshot filename")
        get(device, f"{REMOTE}/outbox/{name}", output / name)
    print(json.dumps({"image": str((output / snapshot['imageFile']).resolve()),
                      "metadata": str(metadata.resolve()), "snapshot": snapshot}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default=os.environ.get("MYPAD_DEVICE_ID", "00008120-001C554628214032"))
    sub = parser.add_subparsers(dest="action", required=True)
    add = sub.add_parser("put", help="Place a PNG or JSON diagram beneath the ink")
    add.add_argument("file", type=Path)
    add.add_argument("--title")
    add.add_argument("--x", type=float, default=140)
    add.add_argument("--y", type=float, default=140)
    add.add_argument("--width", type=float)
    add.add_argument("--height", type=float)
    sub.add_parser("demo", help="Place the example architecture diagram")
    for name in ("capture", "pull"):
        item = sub.add_parser(name, help="Capture current view" if name == "capture" else "Retrieve the last Send to Agent export")
        item.add_argument("--output", type=Path, default=ROOT / "prototype" / ".local" / "exports")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="mypad-bridge-") as temp:
        folder = Path(temp)
        if args.action in ("put", "demo"):
            file = ROOT / "prototype/examples/round-trip.json" if args.action == "demo" else args.file.resolve()
            if not file.is_file():
                raise RuntimeError(f"No such file: {file}")
            if file.suffix.lower() == ".json":
                scene = json.loads(file.read_text())
                command = command_base("scene")
                command["scene"] = {"nodes": scene["nodes"], "edges": scene.get("edges", [])}
                width, height = scene["width"], scene["height"]
            else:
                data = file.read_bytes()
                if data[:8] != b"\x89PNG\r\n\x1a\n":
                    raise RuntimeError("Use a PNG image or a JSON diagram")
                pixel_width, pixel_height = struct.unpack(">II", data[16:24])
                if not pixel_width or not pixel_height:
                    raise RuntimeError("Empty image")
                width = min(1100, pixel_width)
                height = width * pixel_height / pixel_width
                command = command_base("image")
                command["imageFile"] = f"upload-{command['id']}.png"
                put(args.device, file, f"{REMOTE}/assets/{command['imageFile']}")
            command.update(title=(getattr(args, "title", None) or file.stem),
                           x=getattr(args, "x", 140), y=getattr(args, "y", 140),
                           width=getattr(args, "width", None) or width,
                           height=getattr(args, "height", None) or height)
            receipt = publish(args.device, command, folder)
            print(json.dumps({"command": command["id"], "receipt": receipt}, indent=2))
        elif args.action == "capture":
            receipt = publish(args.device, command_base("capture"), folder)
            # Retrieve this capture even if the user creates a newer export.
            metadata_name = Path(receipt["imageFile"]).with_suffix(".json").name
            pull_latest(args.device, args.output.resolve(), metadata_name)
        elif args.action == "pull":
            pull_latest(args.device, args.output.resolve())


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        print(f"canvas-bridge: {error}", file=sys.stderr)
        sys.exit(1)

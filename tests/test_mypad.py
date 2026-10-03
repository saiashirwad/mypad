import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import uuid
import zipfile

spec = importlib.util.spec_from_file_location("mypad", Path(__file__).resolve().parents[1] / "scripts/mypad.py")
mypad = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mypad)


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.identifier = str(uuid.uuid4())
        self.manifest = dict(format="mypad-board", version=1, boardSize=dict(width=3000, height=3000),
                             view=dict(centerX=1500, centerY=1500, zoomScale=1), inkFile="ink.drawing",
                             previewFile="preview.png", references=[dict(id=self.identifier, title="Chart",
                             file=f"assets/{self.identifier}.png", frame=dict(x=140, y=140, width=800, height=600))])
        # Archive validation checks headers; native restore separately decodes actual PNG and PencilKit data.
        png = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 800, 600)
        (self.source / "assets").mkdir()
        (self.source / "preview.png").write_bytes(png)
        (self.source / f"assets/{self.identifier}.png").write_bytes(png)
        (self.source / "ink.drawing").write_bytes(b"native editable ink")

    def tearDown(self):
        self.temporary.cleanup()

    def archive(self, extra=None):
        (self.source / "manifest.json").write_text(json.dumps(self.manifest))
        archive = self.root / "board.mypad"
        with zipfile.ZipFile(archive, "w") as zipped:
            for path in self.source.rglob("*"):
                if path.is_file():
                    zipped.write(path, str(path.relative_to(self.source)))
            if extra:
                zipped.writestr(*extra)
        return archive

    def unpack(self, extra=None):
        target = self.root / "restored"
        target.mkdir()
        return mypad.unpack(self.archive(extra), target)

    def test_round_trip_preserves_editable_state_and_original_assets(self):
        manifest, files = self.unpack()
        self.assertEqual(manifest, self.manifest)
        self.assertEqual((self.root / "restored/ink.drawing").read_bytes(), b"native editable ink")
        self.assertEqual(len(files), 4)

    def test_traversal_is_rejected_without_writing_outside_package(self):
        with self.assertRaises(mypad.Failure):
            self.unpack(("../escaped", b"bad"))
        self.assertFalse((self.root / "escaped").exists())

    def test_unknown_version_rejected(self):
        self.manifest["version"] = 2
        with self.assertRaises(mypad.Failure):
            self.unpack()

    def test_missing_reference_rejected(self):
        (self.source / f"assets/{self.identifier}.png").unlink()
        with self.assertRaises(FileNotFoundError):
            self.unpack()

    def test_duplicate_identity_rejected(self):
        self.manifest["references"].append(self.manifest["references"][0])
        with self.assertRaises(mypad.Failure):
            self.unpack()

    def test_undeclared_asset_rejected(self):
        with self.assertRaises(mypad.Failure):
            self.unpack((f"assets/{uuid.uuid4()}.png", b"extra"))

    def test_nonfinite_geometry_rejected(self):
        self.manifest["references"][0]["frame"]["x"] = float("nan")
        with self.assertRaises(mypad.Failure):
            self.unpack()

    def test_oversized_image_header_rejected(self):
        (self.source / f"assets/{self.identifier}.png").write_bytes(
            b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 50000, 50000))
        with self.assertRaises(mypad.Failure):
            self.unpack()

    def test_symlink_rejected(self):
        archive = self.archive()
        with zipfile.ZipFile(archive, "a") as zipped:
            info = zipfile.ZipInfo(f"assets/{uuid.uuid4()}.png")
            info.create_system = 3
            info.external_attr = 0o120777 << 16
            zipped.writestr(info, "../../outside")
        target = self.root / "restored"
        target.mkdir()
        with self.assertRaises(mypad.Failure):
            mypad.unpack(archive, target)

    def test_capture_receipt_identity_must_match_command(self):
        def fake_copy(device, direction, source, destination, check=True):
            if direction == "from":
                Path(destination).write_text(json.dumps(dict(id=str(uuid.uuid4()), status="ok", revision=1)))
            return True
        with patch.object(mypad, "copy", fake_copy):
            with self.assertRaises(mypad.Failure) as result:
                mypad.publish("device", mypad.make_command("capture"), self.root)
        self.assertEqual(result.exception.code, "invalid_receipt")


if __name__ == "__main__":
    unittest.main()


class CommandTests(unittest.TestCase):
    """Command construction with the device transport mocked out."""

    def setUp(self):
        self.sent = []
        self.copied = []
        patches = [patch.object(mypad, "copy", side_effect=lambda d, direction, source, dest, check=True: self.copied.append((direction, source, dest)) or True),
                   patch.object(mypad, "publish", side_effect=self.publish)]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def publish(self, device, command, folder):
        self.sent.append(dict(command))
        return dict(id=command["id"], status="ok", message="ok", revision=7,
                    reference=dict(id=command.get("target") or command["id"], x=1, y=2, width=640, height=100))

    def run_cli(self, *argv, stdin=""):
        with patch("sys.argv", ["mypad", "--device", "dev", *argv]), patch("sys.stdin.read", return_value=stdin), \
             patch("builtins.print") as printed:
            code = mypad.main()
        return code, json.loads(printed.call_args.args[0])

    def test_write_from_stdin_defaults_to_markdown_and_terse_output(self):
        code, out = self.run_cli("write", "--below", str(uuid.uuid4()), stdin="# hi")
        self.assertEqual(code, 0)
        self.assertEqual(out, dict(ok=True, revision=7, id=self.sent[0]["id"], frame=[1, 2, 640, 100]))
        command = self.sent[0]
        self.assertEqual((command["kind"], command["format"], command["protocolVersion"], command["positioned"]), ("write", "md", 2, False))
        self.assertTrue(self.copied[0][2].endswith(command["sourceFile"]))

    def test_write_infers_format_and_rejects_conflicting_placement(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "shape.svg"
            source.write_text("<svg/>")
            self.run_cli("write", str(source), "--x", "10", "--y", "20")
            self.assertEqual((self.sent[0]["format"], self.sent[0]["positioned"], self.sent[0]["x"]), ("svg", True, 10))
            code, out = self.run_cli("write", str(source), "--x", "10", "--y", "20", "--below", str(uuid.uuid4()))
            self.assertEqual((code, out["code"]), (1, "invalid_input"))

    def test_replace_and_remove_target_a_reference(self):
        target = str(uuid.uuid4())
        self.run_cli("write", "--replace", target, stdin="new text")
        self.run_cli("remove", target)
        self.assertEqual([(c["kind"], c["target"], c["protocolVersion"]) for c in self.sent],
                         [("write", target, 2), ("remove", target, 2)])

    def test_clear_needs_a_revision_or_backup(self):
        code, out = self.run_cli("clear")
        self.assertEqual((code, out["code"], self.sent), (1, "invalid_input", []))

    def test_clear_backup_clears_at_the_backed_up_revision(self):
        real_run = mypad.run
        def fake_run(args):
            if args.action == "backup":
                return dict(ok=True, revision=41, backup=str(args.output))
            return real_run(args)
        with patch.object(mypad, "run", side_effect=fake_run):
            code, out = self.run_cli("clear", "--backup", "/tmp/new.mypad")
        self.assertEqual((code, self.sent[0]["kind"], self.sent[0]["expectedRevision"]), (0, "clear", 41))
        with patch.object(mypad, "run", side_effect=fake_run):
            code, out = self.run_cli("clear", "--backup", "/tmp/new.mypad", "--if-revision", "40")
        self.assertEqual((code, out["code"], out["backup"]), (1, "revision_conflict", "/tmp/new.mypad"))

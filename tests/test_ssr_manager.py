import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest
from unittest.mock import patch
import uuid


spec = importlib.util.spec_from_file_location(
    "ssr_manager", Path(__file__).resolve().parents[1] / "scripts" / "ssr.py")
manager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manager)


class ManagerTests(unittest.TestCase):
    def setUp(self):
        temporary = Path(__file__).resolve().parent / ("tmp-" + uuid.uuid4().hex)
        temporary.mkdir()
        self.addCleanup(shutil.rmtree, temporary)
        self.config = temporary / "config.json"
        self.original = {
            "server_port": 443, "password": "original-password",
            "method": "chacha20-ietf", "protocol_param": "keep-me",
            "udp_enabled": True,
        }
        self.config.write_text(json.dumps(self.original), encoding="utf-8")
        os.chmod(self.config, 0o640)
        self.start_patch(patch.object(manager, "CONFIG", self.config))
        self.start_patch(patch("sys.stdout", new_callable=io.StringIO))
        if os.name == "nt":
            self.start_patch(patch.object(os, "fchown", create=True))
            self.start_patch(patch.object(os, "fchmod", create=True))

    def start_patch(self, patcher):
        result = patcher.start()
        self.addCleanup(patcher.stop)
        return result

    def test_change_preserves_other_fields_and_backup(self):
        with patch.object(manager, "active", return_value=True), \
                patch.object(manager, "service_action") as action:
            self.assertTrue(manager.update_config("server_port", 8443))
        expected = dict(self.original, server_port=8443)
        self.assertEqual(json.loads(self.config.read_text()), expected)
        self.assertEqual(json.loads(self.config.with_name("config.json.bak").read_text()), self.original)
        action.assert_called_once_with("restart")
        if os.name != "nt":
            self.assertEqual(self.config.stat().st_mode & 0o777, 0o640)
            self.assertEqual(self.config.with_name("config.json.bak").stat().st_mode & 0o777, 0o640)

    def test_restart_failure_restores_config_and_previous_state(self):
        for was_active, recovery in ((True, "restart"), (False, "stop")):
            with self.subTest(was_active=was_active), \
                    patch.object(manager, "active", return_value=was_active), \
                    patch.object(manager, "service_action", side_effect=[RuntimeError("failed"), None]) as action:
                original_bytes = self.config.read_bytes()
                with self.assertRaises(RuntimeError):
                    manager.update_config("password", "new-password-123")
                self.assertEqual(self.config.read_bytes(), original_bytes)
                self.assertEqual([call.args[0] for call in action.call_args_list], ["restart", recovery])

    def test_invalid_port_never_changes_config(self):
        with patch.object(manager, "update_config") as update:
            for value in ("0", "65536", "-1", "1.2", "abc", "9" * 100):
                with self.subTest(value=value), patch("builtins.input", return_value=value):
                    with self.assertRaises(ValueError):
                        manager.change_port()
            update.assert_not_called()

    def test_port_conflict_checks_tcp_and_udp(self):
        for responses in (("occupied",), ("", "occupied")):
            results = [subprocess.CompletedProcess([], 0, stdout=value) for value in responses]
            with self.subTest(responses=responses), patch("builtins.input", return_value="8443"), \
                    patch.object(manager, "run", side_effect=results), \
                    patch.object(manager, "update_config") as update:
                with self.assertRaises(ValueError):
                    manager.change_port()
                update.assert_not_called()

    def test_free_port_updates_and_generates_link(self):
        with patch("builtins.input", return_value="08443"), \
                patch.object(manager, "run", return_value=subprocess.CompletedProcess([], 0, stdout="")), \
                patch.object(manager, "update_config", return_value=True) as update, \
                patch.object(manager, "show_link") as link:
            manager.change_port()
            update.assert_called_once_with("server_port", 8443)
            link.assert_called_once()

    def test_password_rules_and_generation(self):
        with patch.object(manager, "update_config", return_value=True) as update, \
                patch.object(manager, "show_link"):
            with patch("builtins.input", return_value="short"):
                with self.assertRaises(ValueError):
                    manager.change_password()
            update.assert_not_called()
            with patch("builtins.input", return_value=""):
                manager.change_password()
            field, password = update.call_args.args
            self.assertEqual(field, "password")
            self.assertRegex(password, r"^[a-f0-9]{32}$")

    def test_menu_continues_after_failed_action(self):
        with patch("builtins.input", side_effect=["2", "4", "0"]), \
                patch.object(manager, "change_port", side_effect=ValueError("bad port")), \
                patch.object(manager, "service_action") as action:
            manager.menu()
            action.assert_called_once_with("restart")

    def test_menu_exits_on_eof(self):
        with patch("builtins.input", side_effect=EOFError):
            manager.menu()

    def test_restart_checks_service_health(self):
        with patch.object(manager, "run") as run, \
                patch.object(manager.time, "sleep"), \
                patch.object(manager, "active", return_value=False):
            with self.assertRaises(RuntimeError):
                manager.service_action("restart")
            run.assert_called_once_with("systemctl", "restart", manager.SERVICE)


if __name__ == "__main__":
    unittest.main()

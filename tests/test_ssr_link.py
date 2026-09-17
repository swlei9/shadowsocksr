#!/usr/bin/env python3
import base64
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "ssr-link.py"


def decode_urlsafe(value):
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4)).decode("utf-8")


class SsrLinkTests(unittest.TestCase):
    def setUp(self):
        self.config = {
            "server_port": 33099,
            "password": "test-password",
            "method": "chacha20-ietf",
            "protocol": "auth_sha1_v4",
            "obfs": "plain",
            "protocol_param": "",
            "obfs_param": "",
        }

    def generate_plain_link(self, address):
        with tempfile.TemporaryDirectory() as temp_dir:
            config_path = Path(temp_dir) / "config.json"
            config_path.write_text(json.dumps(self.config), encoding="utf-8")
            result = subprocess.run(
                ["python3", str(SCRIPT), address, "--config", str(config_path)],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
        self.assertTrue(result.startswith("ssr://"))
        return decode_urlsafe(result.removeprefix("ssr://"))

    def test_ipv6_is_bracketed_in_ssr_uri(self):
        plain = self.generate_plain_link("2001:0db8::1")
        self.assertTrue(plain.startswith("[2001:db8::1]:33099:"), plain)

    def test_bracketed_ipv6_input_is_normalized(self):
        plain = self.generate_plain_link("[2001:db8::2]")
        self.assertTrue(plain.startswith("[2001:db8::2]:33099:"), plain)

    def test_domain_remains_unbracketed(self):
        plain = self.generate_plain_link("SSR6.Example.COM.")
        self.assertTrue(plain.startswith("ssr6.example.com:33099:"), plain)

    def test_invalid_address_is_rejected(self):
        result = subprocess.run(
            ["python3", str(SCRIPT), "https://example.com:443"],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("连接地址格式错误", result.stderr)


if __name__ == "__main__":
    unittest.main()

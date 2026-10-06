import importlib.util
from pathlib import Path
import unittest
from urllib.parse import parse_qs, unquote, urlsplit


spec = importlib.util.spec_from_file_location("deploy", Path(__file__).with_name("deploy.py"))
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class ClientOutputTests(unittest.TestCase):
    def test_clash_and_shadowrocket_share_exact_node_identity(self):
        node = {
            "uuid": "11111111-2222-4333-8444-555555555555",
            "public_key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "short_id": "00000001",
            "port": 443,
            "sni": "www.cloudflare.com",
        }
        clash, link = deploy.client_outputs("203.0.113.10", "EXAMPLE", node)
        self.assertIn('  - name: "EXAMPLE"', clash)
        self.assertIn('      - "EXAMPLE"', clash)
        self.assertIn("    server: 203.0.113.10", clash)
        self.assertIn("      public-key: " + node["public_key"], clash)
        parsed = urlsplit(link)
        self.assertEqual(parsed.scheme, "vless")
        self.assertEqual(parsed.hostname, "203.0.113.10")
        self.assertEqual(parsed.port, 443)
        self.assertEqual(unquote(parsed.fragment), "EXAMPLE")
        self.assertEqual(parse_qs(parsed.query)["pbk"], [node["public_key"]])
        self.assertEqual(parse_qs(parsed.query)["sid"], [node["short_id"]])

    def test_ip_requires_literal_address(self):
        self.assertEqual(deploy.valid_ip("203.0.113.10"), "203.0.113.10")
        with self.assertRaises(ValueError):
            deploy.valid_ip("not-an-ip")
        with self.assertRaises(ValueError):
            deploy.valid_ip("2001:db8::1")


if __name__ == "__main__":
    unittest.main()

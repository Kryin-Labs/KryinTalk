"""Exercise direct SPA navigation without masking missing static assets."""

import http.client
import importlib.util
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "server_web", Path(__file__).parents[1] / "src" / "server_web.py"
)
server_web = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server_web)


class WebRoutingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        Path(self.temp.name, "index.html").write_text("app shell", encoding="utf-8")
        self.original_directory = server_web.DIRECTORY
        server_web.DIRECTORY = self.temp.name
        self.server = ThreadingHTTPServer(
            ("127.0.0.1", 0), server_web.NoCacheHTTPRequestHandler
        )
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        server_web.DIRECTORY = self.original_directory
        self.temp.cleanup()

    def request(self, path):
        connection = http.client.HTTPConnection(*self.server.server_address)
        connection.request("GET", path)
        response = connection.getresponse()
        result = response.status, response.read(), response.getheader("Cache-Control")
        connection.close()
        return result

    def test_direct_routes_serve_app_shell(self):
        for path in ("/groups", "/admin/stats", "/messages/chat?messageId=123"):
            with self.subTest(path=path):
                status, body, cache = self.request(path)
                self.assertEqual(status, 200)
                self.assertEqual(body, b"app shell")
                self.assertIn("no-store", cache)

    def test_missing_assets_remain_not_found(self):
        for path in ("/missing.js", "/assets/missing", "/api/missing"):
            with self.subTest(path=path):
                self.assertEqual(self.request(path)[0], 404)


if __name__ == "__main__":
    unittest.main()

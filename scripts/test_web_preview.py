import tempfile
import threading
import unittest
from functools import partial
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import urlopen
from serve_web_preview import PreviewHandler

class PreviewCheck(unittest.TestCase):
    def test_callback_assets_and_traversal(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, 'index.html').write_text('KryinTalk')
            server = ThreadingHTTPServer(('127.0.0.1', 0), partial(PreviewHandler, directory=directory))
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            base = 'http://127.0.0.1:' + str(server.server_port)
            try:
                with urlopen(base + '/auth/callback') as response:
                    self.assertEqual(response.read(), b'KryinTalk')
                for path in ('/missing.js', '/%2e%2e/secret'):
                    with self.assertRaises(HTTPError) as result:
                        urlopen(base + path)
                    self.assertEqual(result.exception.code, 404)
            finally:
                server.shutdown()
                server.server_close()
                worker.join()

if __name__ == '__main__':
    unittest.main()

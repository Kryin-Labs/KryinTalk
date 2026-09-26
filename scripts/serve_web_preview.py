"""Local Flutter preview. Callback documents work; missing assets stay 404."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1] / 'clients/web/build/web'

class PreviewHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        path = unquote(urlsplit(self.path).path)
        if '\\' in path or '..' in path.split('/'):
            self.send_error(404)
            return
        if path in ('/auth/callback', '/login', '/register', '/check-email', '/access', '/consent'):
            self.path = '/index.html'
        super().do_GET()

if __name__ == '__main__':
    server = ThreadingHTTPServer(('127.0.0.1', 8080), partial(PreviewHandler, directory=str(ROOT)))
    print('KryinTalk preview: http://127.0.0.1:8080/#/register', flush=True)
    server.serve_forever()

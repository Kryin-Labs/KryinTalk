import http.server
import socketserver
from pathlib import Path
from urllib.parse import urlsplit

PORT = 8080
DIRECTORY = str(Path(__file__).resolve().parents[1] / "clients" / "web" / "build" / "web")

class NoCacheHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def send_head(self):
        # Flutter owns navigation routes; missing scripts and API paths must
        # retain a real 404 instead of returning HTML with a success status.
        path = urlsplit(self.path).path
        requested = Path(self.translate_path(self.path))
        if (not requested.exists() and not Path(path).suffix
                and path.split('/')[1] not in {'assets', 'canvaskit', 'icons', 'api'}):
            self.path = '/index.html'
        return super().send_head()

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()

if __name__ == '__main__':
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", PORT), NoCacheHTTPRequestHandler) as httpd:
        print(f"Serving {DIRECTORY} at http://127.0.0.1:{PORT} with NO-CACHE headers")
        httpd.serve_forever()

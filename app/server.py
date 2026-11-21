"""
File server for the DevOps capstone project.

For every client connection the server:
  1. creates a 1KB file of random text inside DATA_DIR (/serverdata)
  2. computes the SHA-256 checksum of the file
  3. sends a one-line JSON header (filename, size, checksum) followed by the file bytes

Wire protocol (all over a single TCP connection):
  {"filename": "...", "size": 1024, "checksum": "<sha256 hex>"}\n
  <exactly `size` bytes of file content>
"""

import hashlib
import json
import logging
import os
import random
import signal
import socket
import socketserver
import string
import sys
from datetime import datetime, timezone

HOST = os.getenv("SERVER_HOST", "0.0.0.0")
PORT = int(os.getenv("SERVER_PORT", "5000"))
DATA_DIR = os.getenv("DATA_DIR", "/serverdata")
FILE_SIZE = int(os.getenv("FILE_SIZE_BYTES", "1024"))
# Keep only the newest N generated files so the volume does not grow forever.
MAX_FILES = int(os.getenv("MAX_FILES", "50"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [server] %(levelname)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger(__name__)


def generate_file() -> str:
    """Create a FILE_SIZE-byte file of random printable text and return its path."""
    os.makedirs(DATA_DIR, exist_ok=True)
    alphabet = string.ascii_letters + string.digits
    content = "".join(random.choices(alphabet, k=FILE_SIZE))

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    path = os.path.join(DATA_DIR, f"data_{timestamp}.txt")
    with open(path, "w", encoding="ascii") as f:
        f.write(content)

    cleanup_old_files()
    return path


def cleanup_old_files() -> None:
    files = sorted(
        (os.path.join(DATA_DIR, name) for name in os.listdir(DATA_DIR) if name.startswith("data_")),
        key=os.path.getmtime,
    )
    for old in files[:-MAX_FILES]:
        os.remove(old)


def sha256_of(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            digest.update(chunk)
    return digest.hexdigest()


class FileHandler(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        client_ip, client_port = self.client_address
        try:
            path = generate_file()
            checksum = sha256_of(path)
            with open(path, "rb") as f:
                payload = f.read()

            header = {
                "filename": os.path.basename(path),
                "size": len(payload),
                "checksum": checksum,
            }
            self.request.sendall((json.dumps(header) + "\n").encode("utf-8"))
            self.request.sendall(payload)
            log.info(
                "Sent %s (%d bytes, sha256=%s) to %s:%s",
                header["filename"], header["size"], checksum, client_ip, client_port,
            )
        except (BrokenPipeError, ConnectionResetError) as exc:
            log.warning("Client %s:%s disconnected early: %s", client_ip, client_port, exc)
        except Exception:
            log.exception("Failed to serve client %s:%s", client_ip, client_port)


class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main() -> None:
    server = ThreadedTCPServer((HOST, PORT), FileHandler)

    def shutdown(signum, _frame):
        log.info("Received signal %s, shutting down", signum)
        server.server_close()
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    log.info("Listening on %s:%d, writing files to %s", HOST, PORT, DATA_DIR)
    server.serve_forever()


if __name__ == "__main__":
    main()

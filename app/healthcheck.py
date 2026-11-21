"""
Docker HEALTHCHECK: succeeds if a socket is LISTENING on SERVER_PORT.

It reads /proc/net/tcp instead of opening a real connection, so health checks
do not trigger file generation on the server.
"""

import os
import sys

port_hex = format(int(os.getenv("SERVER_PORT", "5000")), "04X")
LISTEN_STATE = "0A"

for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)  # skip header
            for line in f:
                fields = line.split()
                local_port = fields[1].split(":")[-1]
                if local_port == port_hex and fields[3] == LISTEN_STATE:
                    sys.exit(0)
    except FileNotFoundError:
        continue

sys.exit(1)

#!/usr/bin/env python3
# mpv_ipc.py -- send a JSON command to mpv via unix socket.
# Usage: mpv_ipc.py <socket> <json-command>
import socket, sys, json
sock_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/fgd_mpv.sock"
cmd = sys.argv[2] if len(sys.argv) > 2 else '{"command":["get_property","pause"]}'
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(1.5)
try:
    s.connect(sock_path)
    s.sendall((cmd + "\n").encode())
    try:
        s.settimeout(0.25)
        data = s.recv(65536)
        sys.stdout.write(data.decode("utf-8", "replace"))
    except socket.timeout:
        pass
except Exception as e:
    sys.stderr.write(str(e) + "\n")
    sys.exit(1)
finally:
    try: s.close()
    except: pass

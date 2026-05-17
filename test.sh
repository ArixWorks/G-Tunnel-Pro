#!/bin/bash
set -euo pipefail

KEY="1234"
MOBILE_CONFIG_FILE="/tmp/test"
CONFIG_SERVER_PORT=8000

nohup python3 -c "
import http.server
KEY='${KEY}'; CF='${MOBILE_CONFIG_FILE}'; PORT=${CONFIG_SERVER_PORT}
class H(http.server.BaseHTTPRequestHandler):
 def log_message(self,*a): pass
 def do_GET(self):
  if self.path=='/configs/'+KEY:
   try: d=open(CF,'rb').read(); self.send_response(200); self.send_header('Content-Type','text/plain'); self.send_header('Content-Length',str(len(d))); self.end_headers(); self.wfile.write(d)
   except: self.send_response(404); self.end_headers()
  elif self.path=='/health': self.send_response(200); self.end_headers(); self.wfile.write(b'ok')
  else: self.send_response(403); self.end_headers()
http.server.HTTPServer(('0.0.0.0',PORT),H).serve_forever()
" >/dev/null 2>&1 &

echo $! > /tmp/pid
disown

echo "Done"

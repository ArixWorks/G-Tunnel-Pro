import http.server
KEY='test'; CF='test'; PORT=8000
class H(http.server.BaseHTTPRequestHandler):
 def log_message(self,*a): pass
 def do_GET(self):
  if self.path=='/configs/'+KEY:
   try: d=open(CF,'rb').read(); self.send_response(200); self.send_header('Content-Type','text/plain'); self.send_header('Content-Length',str(len(d))); self.end_headers(); self.wfile.write(d)
   except: self.send_response(404); self.end_headers()
  elif self.path=='/health': self.send_response(200); self.end_headers(); self.wfile.write(b'ok')
  else: self.send_response(403); self.end_headers()
print("Syntax is OK")

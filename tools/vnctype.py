# minimal RFB client: send key events like a VNC-driven desktop harness. usage: vnctype.py PORT GAP_MS item...
#  item: "key:Return" or "text:/accept"  (text keys are sent press+release back to back)
import socket, struct, sys, time
port=int(sys.argv[1]); gap=float(sys.argv[2])/1000.0
s=socket.create_connection(("127.0.0.1",port))
s.recv(12); s.sendall(b"RFB 003.008\n")
n=s.recv(1)[0]; s.recv(n); s.sendall(b"\x01")
assert struct.unpack(">I", s.recv(4))[0]==0
s.sendall(b"\x01")
hdr=s.recv(24); nl=struct.unpack(">I",hdr[20:24])[0]; s.recv(nl)
KS={"Return":0xff0d," ":0x20}
def key(ks,down): s.sendall(struct.pack(">BBxxI",4,1 if down else 0,ks))
for it in sys.argv[3:]:
    kind,val=it.split(":",1)
    seq=[KS[val]] if kind=="key" else [KS.get(c,ord(c)) for c in val]
    for ks in seq:
        key(ks,True); 
        if gap: time.sleep(gap)
        key(ks,False)
        if gap: time.sleep(gap)
time.sleep(0.3); s.close()

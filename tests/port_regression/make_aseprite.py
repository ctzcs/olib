from pathlib import Path
import struct,zlib
pack=struct.pack
name='图层'.encode()
def chunk(kind,data): return pack('<IH',len(data)+6,kind)+data
def cel(kind,payload): return chunk(0x2005,pack('<HhhBHh',0,0,0,255,kind,0)+b'\0'*5+payload)
layer=chunk(0x2004,pack('<HHHHHHB',1,0,0,0,0,0,255)+b'\0'*3+pack('<H',len(name))+name)
first=cel(2,pack('<HH',1,1)+zlib.compress(bytes([255,32,0,255])))
second=cel(1,pack('<H',0))
def frame(chunks):
    payload=b''.join(chunks)
    return pack('<IHHHHI',16+len(payload),0xf1fa,len(chunks),100,0,0)+payload
frames=frame([layer,first])+frame([second])
header=bytearray(128)
struct.pack_into('<IHHHHH',header,0,128+len(frames),0xa5e0,2,1,1,32)
header[28]=255
Path('tests/port_regression/linked.aseprite').write_bytes(header+frames)

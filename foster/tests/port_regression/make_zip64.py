from pathlib import Path
import struct,zlib
name=b'nested\\zip64.txt';data=b'zip64 payload';crc=zlib.crc32(data)
localextra=struct.pack('<HHQQ',1,16,len(data),len(data))
local=struct.pack('<IHHHHHIIIHH',0x04034b50,45,0,0,0,0,crc,0xffffffff,0xffffffff,len(name),len(localextra))+name+localextra+data
extra=struct.pack('<HHQQQ',1,24,len(data),len(data),0)
central=struct.pack('<IHHHHHHIIIHHHHHII',0x02014b50,45,45,0,0,0,0,crc,0xffffffff,0xffffffff,len(name),len(extra),0,0,0,0,0xffffffff)+name+extra
end64=struct.pack('<IQHHIIQQQQ',0x06064b50,44,45,45,0,0,1,1,len(central),len(local))
locator=struct.pack('<IIQI',0x07064b50,0,len(local)+len(central),1)
# A signature inside the comment must not be mistaken for the real end record.
comment=b'comment:'+struct.pack('<IH',0x06054b50,1)+b'\x00'*16+b'end'
end=struct.pack('<IHHHHIIH',0x06054b50,0,0,0xffff,0xffff,0xffffffff,0xffffffff,len(comment))+comment
Path('tests/port_regression/zip64.zip').write_bytes(local+central+end64+locator+end)

# peek.py ADDR...: read one 32-bit word per physical address from /dev/mem, flushing before each
# access (a bus error kills the process, the words read so far stay printed). Run on the phone as root.
import mmap, os, struct, sys
fd = os.open('/dev/mem', os.O_RDONLY | os.O_SYNC)
for a in sys.argv[1:]:
    a = int(a, 16)
    base = a & ~0xfff
    m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ, offset=base)
    print(f"{a:08x} ", end="", flush=True)
    print(f"{struct.unpack_from('<I', m, a - base)[0]:08x}", flush=True)

/* physdump ADDR...: print each 4 KB page at the physical addresses as "addr value" lines */
#define _FILE_OFFSET_BITS 64
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	int fd = open("/dev/mem", O_RDONLY | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	for (int i = 1; i < argc; i++) {
		uint64_t p = strtoull(argv[i], NULL, 16);
		volatile uint32_t *m = mmap(NULL, 4096, PROT_READ, MAP_SHARED, fd, (off_t)p);
		if (m == MAP_FAILED) { perror("mmap"); return 1; }
		for (int o = 0; o < 1024; o++)
			printf("%08llx %08x\n", (unsigned long long)(p + o * 4), m[o]);
		munmap((void *)m, 4096);
	}
	return 0;
}

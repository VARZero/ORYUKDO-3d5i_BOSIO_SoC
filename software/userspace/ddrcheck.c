// Check RAM owned by this process. /proc/self/pagemap supplies actual PFNs.
#define _GNU_SOURCE
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

int main(void) {
    const size_t page = 4096, pages = 160 * 256;
    int fd = open("/proc/self/pagemap", O_RDONLY);
    volatile uint32_t *mem = mmap(NULL, pages * page, PROT_READ | PROT_WRITE,
                                  MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (fd < 0 || mem == MAP_FAILED) { perror("ddrcheck"); return 1; }
    uint32_t lo = UINT32_MAX, hi = 0;
    size_t used = 0, high_pages = 0;
    for (; used < pages && high_pages < 16; used++) {
        size_t word = used * page / sizeof(*mem);
        mem[word] = 0x39a7f184u ^ used;
        mem[word+1023] = ~mem[word];
        uint64_t entry;
        off_t off = ((uintptr_t)&mem[word] / page) * (off_t)sizeof(entry);
        if (pread(fd, &entry, sizeof(entry), off) != sizeof(entry)) { perror("pagemap"); return 1; }
        uint64_t pa = (entry & ((UINT64_C(1)<<55)-1)) * page;
        if (!(entry >> 63) || pa < 0x80000000u || pa >= 0xc0000000u) {
            fprintf(stderr, "invalid or masked PFN 0x%" PRIx64 "\n", pa); return 1;
        }
        if (pa >= 0x88000000u) {
            high_pages++;
            if (pa < lo) lo = pa;
            if (pa > hi) hi = pa;
        }
    }
    for (size_t i = 0; i < used; i++) {
        size_t word = i * page / sizeof(*mem);
        uint32_t pattern = 0x39a7f184u ^ i;
        if (mem[word] != pattern || mem[word+1023] != ~pattern) {
            fprintf(stderr, "readback failed at page %zu\n", i); return 1;
        }
    }
    if (high_pages < 16) { fputs("insufficient upper-memory coverage\n", stderr); return 1; }
    printf("DDR_HIGH_OK pages=%zu first_pa=0x%08" PRIx32 " last_pa=0x%08" PRIx32 "\n",
           high_pages, lo, hi + 4092);
    munmap((void *)mem, pages*page); close(fd);
    return 0;
}

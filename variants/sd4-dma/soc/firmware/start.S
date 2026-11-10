.section .text.start
.globl _start
_start:
    lui sp, 0x8007f
    call main
1:  j 1b

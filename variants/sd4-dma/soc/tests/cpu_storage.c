typedef unsigned int u32;
#define R(a) (*(volatile u32 *)(a))
#define DMA 0x10009000u
#define PLIC 0x0c000000u
#define SD 0x10008000u
static volatile u32 count,status,expected_source;
static void fail(u32 n){R(0x8007ff00)=0xbad00000|n;for(;;)__asm__ volatile("nop");}
static void check(int ok,u32 n){if(!ok)fail(n);}
static void fence(void){__asm__ volatile("fence iorw,iorw":::"memory");}
static void service(u32 context,u32 expected){
 u32 cause;if(expected==11)__asm__ volatile("csrr %0,mcause":"=r"(cause));
 else __asm__ volatile("csrr %0,scause":"=r"(cause));
 check(cause==(0x80000000|expected),1);
 u32 source=R(PLIC+context+4);if(!source)return;
 check(source==expected_source,2);u32 reg=source==1?SD+12:DMA+20;
 status=R(reg);check(status&2,3);
 R(reg)=2;fence();R(PLIC+context+4)=source;fence();count++;
}
void __attribute__((interrupt("machine"),aligned(4))) machine_handler(void){service(0x200000,11);}
void __attribute__((interrupt("supervisor"),aligned(4))) supervisor_handler(void){service(0x201000,9);}
static void wait_done(void){for(u32 n=0;n<10000;n++){if(count)return;}fail(4);}
static void sector(u32 command,u32 lba,u32 address){
 count=0;expected_source=1;
 R(SD+24)=address;R(SD+28)=512;R(SD+4)=lba;fence();
 R(SD+8)=command|0x340|(command==24?0x400:0);
 wait_done();check(!(status&0x70),11);check(count==1,12);
}
static void supervisor_main(void){
 count=0;expected_source=2;R(DMA+4)=0x80015000;R(DMA+8)=256;R(DMA+12)=0x739ac15e;fence();R(DMA+16)=0x102;
 wait_done();check((status&6)==2,5);
 for(u32 n=0;n<64;n++)check(R(0x80015000+n*4)==0x739ac15e,6);
 check(count==1,7);
#ifdef KFB_NATIVE_BACKEND
 count=0;R(DMA+4)=0xbfffff00;R(DMA+8)=256;R(DMA+12)=0x548c19e7;fence();R(DMA+16)=0x102;
 wait_done();check((status&6)==2,16);
 for(u32 n=0;n<64;n++)check(R(0xbfffff00+n*4)==0x548c19e7,17);
#endif
 R(0x8007ff00)=0x600d0004;for(;;)__asm__ volatile("nop");
}
int main(void){
 R(0x8007ff00)=0;count=0;status=0;expected_source=2;
 for(u32 n=0;n<64;n++)R(0x80011ff0+n*4)=n*0x1030719+0x18273645;
 R(PLIC+8)=3;R(PLIC+0x2000)=4;R(PLIC+0x200000)=0;
 __asm__ volatile("csrw mtvec,%0"::"r"(machine_handler));
 __asm__ volatile("csrw mie,%0"::"r"(0x800));__asm__ volatile("csrsi mstatus,8");
 R(DMA)=0x80011ff0;R(DMA+4)=0x80013ff8;R(DMA+8)=256;fence();R(DMA+16)=0x101;
 wait_done();check((status&6)==2,8);
 for(u32 n=0;n<64;n++)check(R(0x80013ff8+n*4)==n*0x1030719+0x18273645,9);
 check(count==1,10);
 R(PLIC+4)=2;R(PLIC+0x2000)=6;
 check(R(SD)==0x53443431,13);R(SD+16)=2;R(SD+20)=1;R(SD+48)=1;
 sector(17,4096,0x80016000);
 for(u32 n=0;n<128;n++){
  u32 expected=0;for(u32 b=0;b<4;b++)expected|=(((4*n+b)*29+11)&255)<<(8*b);
  check(R(0x80016000+n*4)==expected,14);
 }
 sector(24,4097,0x80016000);sector(17,4097,0x80017000);
 for(u32 n=0;n<128;n++)check(R(0x80016000+n*4)==R(0x80017000+n*4),15);
#ifdef KFB_NATIVE_BACKEND
 sector(17,4096,0xbffff000);
 for(u32 n=0;n<128;n++)check(R(0xbffff000+n*4)==R(0x80016000+n*4),18);
#endif
 __asm__ volatile("csrci mstatus,8");
 R(PLIC+0x2000)=0;R(PLIC+0x2080)=4;R(PLIC+0x201000)=0;
 __asm__ volatile("csrw stvec,%0"::"r"(supervisor_handler));
 __asm__ volatile("csrw mideleg,%0; csrw mie,%0"::"r"(0x200));
 __asm__ volatile("csrw mepc,%0"::"r"(supervisor_main));
 u32 ms;__asm__ volatile("csrr %0,mstatus":"=r"(ms));ms=(ms&~0x1808u)|0x802;
 __asm__ volatile("csrw mstatus,%0; mret"::"r"(ms):"memory");return 0;
}

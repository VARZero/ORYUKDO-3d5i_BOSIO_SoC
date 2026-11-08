typedef unsigned int u32;
#define R(a) (*(volatile u32 *)(a))
#define DONE 0x8007ff00u
static void fail(u32 c) {R(DONE)=0xbad00000u|c;for(;;) __asm__ volatile("nop");}
static void check(int ok,u32 code) {if(!ok)fail(code);}
static void fence(void) {__asm__ volatile("fence iorw,iorw":::"memory");}
static void uart(const char *s) {while(*s){while(!(R(0x10000004)&0x2000)){} R(0x10000000)=(unsigned char)*s++;}}
static u32 csr_time(void){u32 v;__asm__ volatile("rdtime %0":"=r"(v));return v;}
static u32 lr(volatile u32 *p){u32 v;__asm__ volatile("lr.w.aq %0,(%1)":"=r"(v):"r"(p):"memory");return v;}
static u32 sc(volatile u32 *p,u32 v){u32 r;__asm__ volatile("sc.w.rl %0,%2,(%1)":"=r"(r):"r"(p),"r"(v):"memory");return r;}
static u32 amo(volatile u32 *p,u32 v){u32 r;__asm__ volatile("amoadd.w.aqrl %0,%2,(%1)":"=r"(r):"r"(p),"r"(v):"memory");return r;}
static void setup(u32 core,u32 desc,u32 scene,u32 color) {
    volatile u32 *d=(volatile u32 *)desc;
    for(u32 n=0;n<18;n++)d[n]=0;
    d[2]=1;d[3]=1;d[4]=1;d[5]=(color<<8)|1;d[14]=0xffffffffu;
    R(core+0x18)=0x80010000;R(core+0x1c)=0;
    R(core+0x24)=desc;R(core+0x28)=0;
    R(core+0x30)=scene;R(core+0x34)=0;
    R(core+0x3c)=1;R(core+0x44)=18;R(core+0x4c)=256;R(core+0x54)=1;
    R(core+4)=1;R(core+8)=1;
}
static void wait_done(u32 core,u32 code) {
    for(u32 n=0;n<20000;n++) if(R(core)&2){check(R(core+0x10)==0,code);return;}
    fail(code+1);
}
int main(void) {
    const u32 p0=0x20000000,p1=0x20010000,out=0x20020000;
    R(DONE)=0;
    check(R(0x10004008)==0x41584931,1);
    // Additional AXI peripherals: wire loopback UART/SPI, no I2C slave => NACK.
    *(volatile unsigned char *)0x10005003=0x80;
    *(volatile unsigned char *)0x10005000=1;*(volatile unsigned char *)0x10005001=0;
    *(volatile unsigned char *)0x10005003=3;
    *(volatile unsigned char *)0x10005000=0x5a;
    u32 io=0;for(u32 n=0;n<1000;n++){io=R(0x10005004);if(io&0x100)break;}
    check(io&0x100,30);check((R(0x10005000)&255)==0x5a,31);
    R(0x10006008)=8;R(0x10006000)=0xa6;R(0x10006010)=1;
    for(u32 n=0;n<1000;n++){io=R(0x10006004);if(io&2)break;}
    check((io&3)==2 && R(0x10006000)==0xa6,32);
    R(0x10007008)=8;R(0x10007000)=0xa0;R(0x10007010)=11;
    for(u32 n=0;n<1000;n++){io=R(0x10007004);if(io&2)break;}
    check((io&63)==6,33);
    check(R(out+0x50)==0x44544631 && R(out+0x38)==16384,7);
    u32 t=csr_time();check(csr_time()>=t,8);
    R(0x02004004)=0;R(0x02004000)=0;
    u32 pending=0;for(u32 n=0;n<100;n++){__asm__ volatile("csrr %0,mip":"=r"(pending));if(pending&128)break;}
    check(pending&128,9);R(0x02004004)=0xffffffffu;R(0x02004000)=0xffffffffu;
    setup(p0,0x80011000,0x80020000,0xe0);setup(p1,0x80011100,0x80021000,0x1c);
    // Mock DDR starts cleared, matching the board SD loader's clear pass.
    // Keep the original uniform scene as a regression; the patterned variant
    // distinguishes directory selection, word addresses and byte lanes.
#ifdef PATTERN_SCENE
    for(u32 n=0;n<256;n++) R(0x80030000+n*4)=(n*0x010101u)^0x5a3cc3u;
    R(0x80030400+177*4)=256;
    for(u32 n=0;n<260;n++) {
        u32 word=0;
        for(u32 lane=0;lane<4;lane++) word|=((n*4+lane)%251+1)<<(lane*8);
        R(0x800345f0+n*4)=word;
    }
#else
    R(0x80030008)=0xabcdef;
    for(u32 n=0;n<260;n++) R(0x800345f0+n*4)=0x02020202;
#endif
    R(out+8)=0x80030000;R(out+0xc)=4736;
    R(out+0x60)=0;
    for(u32 n=0;n<180;n++) R(out+0x64)=(n%3==0)?1:0;
    R(out+0x68)=1;
    R(0x10004000)=1;check(R(0x10004000)==1,28);
    R(0x10004000)=0;check(R(0x10004004)==0,29);
    fence();R(p0)=1;R(p1)=1;R(out+0x6c)=1;
    wait_done(p0,10);wait_done(p1,12);
    check(R(0x80020000)==0xe0e0e0e0 && R(0x800203fc)==0xe0e0e0e0,14);
    check(R(0x80021000)==0x1c1c1c1c && R(0x800213fc)==0x1c1c1c1c,15);
    u32 received=0;for(u32 n=0;n<20000;n++){received=R(out+0x70);if(received==4480)break;}
    check(received==4480 && !(R(out+4)&32),16);
    R(out)=1; // Start real RGB stream after scene prefetch.
    check((R(0x10004010)&3)==3,17); // Both HLS completion IRQs reached system status.
    // LR reservation must be invalidated by an actual projection DMA write.
    volatile u32 *shared=(volatile u32 *)0x80020000;
    check(lr(shared)==0xe0e0e0e0,18);
    R(0x80011014)=0x6301;fence();R(p0)=1;wait_done(p0,19);
    check(sc(shared,7)==1 && *shared==0x63636363,21);
    (void)lr(shared);check(sc(shared,11)==0 && *shared==11,22);
    check(amo(shared,1)==11 && *shared==12,23);
    uart("GEN3 BOSIO SOC OK\n");
    R(DONE)=0x600d0001;
    for(;;)__asm__ volatile("nop");
}

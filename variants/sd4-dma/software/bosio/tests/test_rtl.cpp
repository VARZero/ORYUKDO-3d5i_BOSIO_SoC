#include "Vtb_bosio_driver.h"
#include "verilated.h"
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <vector>
extern "C" {
#include "../common/bosio_demo.h"
}
static void check(bool ok,const char *s){if(!ok)throw std::runtime_error(s);}
struct Bench {
 Vtb_bosio_driver d;
 bo_engine engine{};
 unsigned long long cycles=0,pixels=0,frames=0;
 unsigned seed,frame_epoch=0;
 bool monitor=false,stalled=false,held=false;
 unsigned held_data=0,held_marks=0;
 std::vector<unsigned> scene[2];
 unsigned desc[2][18]{};
 Bench(unsigned s):seed(s){
  d.clk=0;d.reset_n=0;d.control_valid=0;d.mem_we=0;d.mem_index=0;d.video_ready=0;
  for(int i=0;i<20;i++)tick();d.reset_n=1;for(int i=0;i<20;i++)tick();
  bo_io io{this,read_cb,write_cb,now_cb,delay_cb,barrier_cb};bo_init(&engine,&io,0x80000000);
 }
 void tick(){
  d.clk=0;d.video_ready=!stalled&&((cycles+seed)%7!=0)&&((cycles*13+seed)%19!=0);d.eval();
  if(monitor){
   if(held)check(d.video_valid&&d.video_data==held_data&&((d.video_sof<<1)|d.video_eol)==held_marks,"backpressure changed pixel");
   held=d.video_valid&&!d.video_ready;held_data=d.video_data;held_marks=(d.video_sof<<1)|d.video_eol;
   if(d.video_valid&&d.video_ready){
    unsigned x=pixels%1280,y=(pixels/1280)%720;
    check(bool(d.video_sof)==(x==0&&y==0),"SOF mismatch");check(bool(d.video_eol)==(x==1279),"EOL mismatch");
    if(d.video_sof){frame_epoch=d.video_data==0x0000ff?1:0;frames++;}
    unsigned expected=frame_epoch?(x<=640?0x0000ff:0xffff00):(x<=640?0xff0000:0x00ff00);
    if(d.video_data!=expected){std::fprintf(stderr,"pixel %llu xy=%u,%u got=%06x expected=%06x epoch=%u\n",pixels,x,y,d.video_data,expected,frame_epoch);throw std::runtime_error("pixel scoreboard");}
    pixels++;
   }
  }
  d.clk=1;d.eval();cycles++;
 }
 int access(unsigned core,unsigned reg,unsigned *v,bool write){
  d.control_valid=1;d.control_write=write;d.control_address=0x20000000+core*0x10000+reg;d.control_wdata=*v;
  for(unsigned n=0;n<200000;n++){tick();if(d.control_done){*v=d.control_rdata;int r=d.control_error?-EIO:0;d.control_valid=0;tick();return r;}}
  throw std::runtime_error("AXI MMIO timeout");
 }
 static int read_cb(void *p,unsigned c,__u32 r,__u32 *v){return ((Bench*)p)->access(c,r,v,false);}
 static int write_cb(void *p,unsigned c,__u32 r,__u32 v){return ((Bench*)p)->access(c,r,&v,true);}
 static __u64 now_cb(void *p){return ((Bench*)p)->cycles/100;}
 static void delay_cb(void *p,unsigned us){auto *b=(Bench*)p;for(unsigned n=0;n<us*100;n++)b->tick();}
 static void barrier_cb(void *p){((Bench*)p)->tick();}
 void upload(unsigned region,const unsigned *data,unsigned words){
  check(bo_upload_check(&engine,region,0,words*4)==0,"upload rejected");
  for(unsigned n=0;n<words;n++){d.mem_index=bo_offsets[region]/4+n;d.mem_wdata=data[n];d.mem_we=1;tick();}
  d.mem_we=0;
 }
 unsigned peek(unsigned addr){d.mem_index=addr/4;d.eval();return d.mem_rdata;}
 void build(unsigned bank,bool second){
  scene[bank].resize(BO_DEMO_WORDS);bo_demo_scene(scene[bank].data());
  unsigned texture[2]={second?0x0000ffu:0xff0000u,second?0xffff00u:0x00ff00u};
  bo_demo_descriptor(desc[0],0,0x63);bo_demo_descriptor(desc[1],1,0x63);
  upload(BO_SCENE0+bank,scene[bank].data(),BO_DEMO_WORDS);upload(BO_TEXTURE,texture,2);
  upload(BO_DESC0,desc[0],18);upload(BO_DESC1,desc[1],18);
 }
 struct bo_run job(unsigned bank){struct bo_run j{};j.bank=bank;j.scene_words=BO_DEMO_WORDS;j.texture_words=2;j.jobs[0]=j.jobs[1]=1;j.timeout_ms=100;return j;}
 struct bo_present present(unsigned bank){struct bo_present p{};p.bank=bank;p.scene_words=BO_DEMO_WORDS;p.resolution=2;p.timeout_ms=100;bo_demo_camera(p.camera);return p;}
 void run(unsigned bank,bool second){
  auto j=job(bank);int rc=bo_run(&engine,&j,desc[0],desc[1]);
  std::printf("PROJECT bank=%u rc=%d status=%u,%u cells=%u,%u\n",bank,rc,j.status[0],j.status[1],j.cells[0],j.cells[1]);
  check(!rc,"project run failed");
  for(unsigned c=0;c<2;c++)for(unsigned n=0;n<256;n++){
   unsigned idx=second?(c?0xfcu:3u):(c?0x1cu:0xe0u);
   unsigned value=peek(bo_offsets[BO_SCENE0+bank]+(BO_HEADER_WORDS+c*256+n)*4);
   if(value!=idx*0x01010101u){std::fprintf(stderr,"tile c=%u n=%u got=%08x expected=%08x\n",c,n,value,idx*0x01010101u);throw std::runtime_error("projection tile mismatch");}
  }
  check(j.cells[0]==1024&&j.cells[1]==1024,"written_cells count");
  check(peek(bo_offsets[BO_SCENE0+bank]+(BO_HEADER_WORDS-1)*4)==0xffffffffu,"metadata clobbered");
  check(peek(bo_offsets[BO_SCENE0+bank]+(BO_HEADER_WORDS+512)*4)==0xcccccccc,"tail guard clobbered");
 }
};
int main(int argc,char **argv){
 try{
  Verilated::commandArgs(argc,argv);unsigned seed=argc>1?std::strtoul(argv[1],nullptr,0):1;Bench b(seed);
  struct bo_info info{};check(!bo_info(&b.engine,&info)&&info.signature==0x42533235,"signature");
  b.build(0,false);
  auto bad=b.job(0);auto before=b.cycles;
  b.desc[1][1]=b.desc[0][1];check(bo_run(&b.engine,&bad,b.desc[0],b.desc[1])==-EINVAL,"overlap accepted");
  check(b.cycles==before,"validation touched hardware");bo_demo_descriptor(b.desc[1],1,0x63);
  bad=b.job(0);bad.jobs[0]=65;check(bo_run(&b.engine,&bad,b.desc[0],b.desc[1])==-EINVAL,"oversized jobs accepted");
  bad=b.job(0);bad.jobs[0]=bad.jobs[1]=0;before=b.cycles;check(!bo_run(&b.engine,&bad,b.desc[0],b.desc[1])&&b.cycles==before,"no-op launched hardware");
  b.run(0,false);auto p=b.present(0);b.monitor=true;
  check(!bo_present(&b.engine,&p,b.scene[0].data()),"first presentation");
  check(bo_upload_check(&b.engine,BO_SCENE0,0,4)==-EBUSY,"active overwrite accepted");
  bad=b.job(0);check(bo_run(&b.engine,&bad,b.desc[0],b.desc[1])==-EBUSY,"active DMA accepted");
  while(b.pixels<1280*3)b.tick();
  b.build(1,true);b.run(1,true);p=b.present(1);
  check(!bo_present(&b.engine,&p,b.scene[1].data()),"second presentation");
  while(b.frames<3 || b.pixels%921600<1280*3)b.tick();
  check(b.frame_epoch==1,"new frame not observed");
  check(b.d.writes0==512&&b.d.writes1==512,"missing projector DMA writes");
  check(b.d.reads_out>=8960,"output did not fetch scenes");
  check(!bo_upload_check(&b.engine,BO_SCENE0,0,4),"old scene not released after active-base ack");
  std::printf("PASS DUAL_TO_OUTPUT seed=%u cycles=%llu pixels=%llu frames=%llu dma_writes=%u,%u output_reads=%u\n",seed,b.cycles,b.pixels,b.frames,b.d.writes0,b.d.writes1,b.d.reads_out);
  /* A blocked frame switch must time out and freeze all buffer reuse. */
  b.stalled=true;p=b.present(0);p.timeout_ms=1;
  check(bo_present(&b.engine,&p,b.scene[0].data())==-ETIMEDOUT,"missing frame timeout");
  check(b.engine.poisoned&&bo_upload_check(&b.engine,BO_TEXTURE,0,4)==-EIO,"timeout permits DMA buffer reuse");
  std::puts("PASS OWNERSHIP validation/no-op/active-write/retire/timeout-quarantine");return 0;
 }catch(const std::exception &e){std::fprintf(stderr,"FAIL %s\n",e.what());return 1;}
}

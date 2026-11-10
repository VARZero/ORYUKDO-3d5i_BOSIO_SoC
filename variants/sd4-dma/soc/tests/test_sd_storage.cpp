#include "Vtb_sd_storage.h"
#include <verilated.h>
#include "native_card_model.hpp"
#include <iostream>
#include <cstring>
#include <fstream>
static uint32_t crc32(const std::array<unsigned char,512>& b){uint32_t c=~0u;for(auto x:b){c^=x;for(int i=0;i<8;i++)c=(c>>1)^((c&1)?0xedb88320:0);}return ~c;}
int main(int argc,char**argv){
 std::string mode=argc>1?argv[1]:"good";
 bool expected_failure=mode!="good" && mode!="image";
 try{
 Verilated::commandArgs(argc,argv);Vtb_sd_storage d;Card card;
 for(unsigned sec=2049;sec<2052;sec++)for(int i=0;i<512;i++)card.disk[sec][i]=(i*31+sec)&255;
 auto &h=card.disk[2048];memcpy(h.data(),"ORYSD001",8);
 auto le=[&](int off,uint32_t v){for(int j=0;j<4;j++)h[off+j]=v>>(j*8);};
 for(int i=0;i<3;i++){le(8+8*i,1);le(12+8*i,crc32(card.disk[2049+i]));}
 if(mode=="image"){
  check(argc>2,"image path required");std::ifstream file(argv[2],std::ios::binary);check(bool(file),"open boot image");
  file.seekg(2048*512);unsigned lba=2048;
  while(file.read(reinterpret_cast<char*>(card.disk[lba].data()),512))++lba;
  card.disk.erase(lba);check(lba>2051,"boot image too small");
 }
 if(mode=="header")h[0]^=1;
 else if(mode=="oversize")le(8,8193);
 else if(mode=="payload-crc")card.disk[2049][0]^=1;
 else if(mode=="card-crc")card.bad_crc=true;
 else check(mode=="good" || mode=="ddr" || mode=="image","unknown test mode");
 std::map<unsigned,std::array<uint32_t,8>> dram;
 bool pending=false;unsigned pending_addr=0,cycles=0;
 auto tick=[&](){
  d.clk=0;d.app_rdy=cycles%5!=0;d.app_wdf_rdy=cycles%7!=0;
  d.rd_valid=pending;if(pending)for(int i=0;i<8;i++)d.rd_data[i]=dram[pending_addr][i];
  if(pending && mode=="ddr")d.rd_data[0]^=1;
  d.eval();bool prev=d.sd_clk,read=d.boot_en&&!d.boot_wr&&d.app_rdy;
  unsigned ra=d.boot_addr;
  if(d.boot_wen){check(d.app_rdy && d.app_wdf_rdy,"loader write acceptance");for(int i=0;i<8;i++)dram[d.boot_addr][i]=d.boot_data[i];}
  d.clk=1;d.eval();cycles++;
  if(!prev&&d.sd_clk)card.rise(d);if(prev&&!d.sd_clk)card.fall(d);d.eval();
  pending=read;pending_addr=ra;
  check(cycles<(mode=="image"?200000000u:6000000u),"storage timeout");check(!d.boot_failed,"native boot failed");
 };
 d.reset_n=0;d.sd_cmd_i=1;d.sd_dat_i=15;d.awvalid=0;d.wvalid=0;d.bready=0;d.arvalid=0;d.rready=0;d.select_dma=0;
 for(int i=0;i<5;i++)tick();d.reset_n=1;
 while(!d.boot_done)tick();for(int i=0;i<10;i++)tick();
 check(!expected_failure,"bad image unexpectedly booted");
 unsigned bases[]={0,0x100000,0x1fc0000};
 unsigned segment_lba=2049;
 for(int seg=0;seg<3;seg++){
  unsigned count=0;for(int j=0;j<4;j++)count|=unsigned(h[8+8*seg+j])<<(8*j);
  for(unsigned i=0;i<count*512;i++){
   unsigned wa=bases[seg]+i/4;auto word=dram[wa&~7u][wa&7];
   check(((word>>(8*(i%4)))&255)==card.disk[segment_lba+i/512][i%512],"boot DDR payload/CRC mapping");
  }
  segment_lba+=count;
 }
 std::cout<<"PASS native SD boot initialization, header and 3 CRC-checked segments to mock DDR cycles="<<cycles<<"\n";
 auto put=[&](unsigned a,uint32_t v,bool dma=false){
  d.select_dma=dma;d.address=a;d.write_data=v;d.awvalid=1;d.wvalid=1;bool ah=false,wh=false;
  while(!ah||!wh){d.clk=0;d.eval();bool aa=d.awvalid&&d.awready,ww=d.wvalid&&d.wready;tick();if(aa)ah=true;if(ww)wh=true;d.awvalid=!ah;d.wvalid=!wh;}
  d.bready=1;while(!d.bvalid)tick();check(!d.bresp,"MMIO write error");tick();d.bready=0;
 };
 auto get=[&](unsigned a,bool dma=false){
  d.select_dma=dma;d.address=a;d.arvalid=1;d.clk=0;d.eval();while(!d.arready)tick();tick();d.arvalid=0;
  d.rready=1;while(!d.rvalid)tick();check(!d.rresp,"MMIO read error");auto v=d.read_data;tick();d.rready=0;return v;
 };
 check(get(0)==0x53443431,"host version");put(48,1);put(16,2);put(20,1);
 auto cmd=[&](unsigned c,unsigned arg,unsigned len,unsigned addr,bool fail=false){
  put(24,addr);put(28,len);put(4,arg);put(8,c);
  while(!d.sd_irq)tick();auto status=get(12);put(12,2);check(bool(status&0x70)==fail,"runtime SD command status");
 };
 cmd(17|(1<<6)|(1<<8)|(1<<9),2049,512,0x80002000);
 for(int i=0;i<128;i++){d.peek_word=0x2000/4+i;d.eval();uint32_t v=0;for(int j=0;j<4;j++)v|=uint32_t(card.disk[2049][i*4+j])<<(8*j);check(d.peek_data==v,"runtime SD DMA read");}
 put(4,0x80004000,true);put(8,512,true);put(12,0xab3917e5,true);put(16,0x102,true);
 while(!d.dma_irq)tick();check(!(get(20,true)&4),"runtime fill");put(20,2,true);
 cmd(24|(1<<6)|(1<<8)|(1<<9)|(1<<10),4096,512,0x80004000);
 for(int i=0;i<512;i++)check(card.disk[4096][i]==((0xab3917e5u>>(8*(i%4)))&255),"runtime SD DMA write");
 // Read back the written block through the independent receive path.
 cmd(17|(1<<6)|(1<<8)|(1<<9),4096,512,0x80005000);
 for(int i=0;i<128;i++){d.peek_word=0x5000/4+i;d.eval();check(d.peek_data==0xab3917e5,"runtime disk roundtrip");}
 card.bad_crc=true;
 cmd(17|(1<<6)|(1<<8)|(1<<9),2049,512,0x80005000,true);
 for(int i=0;i<128;i++){d.peek_word=0x5000/4+i;d.eval();check(d.peek_data==0xab3917e5,"CRC-failed sector changed DDR");}
 card.bad_crc=false;cmd(17|(1<<6)|(1<<8)|(1<<9),4096,512,0x80005000);
 std::cout<<"PASS boot-to-runtime ownership, MMIO command, SD->DMA->RAM, fill, RAM->DMA->SD, sector roundtrip cycles="<<cycles<<"\n";
 }catch(const std::exception&e){
  if(expected_failure && std::string(e.what())=="native boot failed"){
   std::cout<<"PASS native boot rejects "<<mode<<" before CPU release\n";return 0;
  }
  std::cerr<<"FAIL "<<e.what()<<"\n";return 1;
 }}

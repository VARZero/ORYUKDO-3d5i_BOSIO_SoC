#include "Vor_sd_native.h"
#include <verilated.h>
#include <array>
#include <deque>
#include <stdexcept>
#include <iostream>
static void check(bool v,const char *s){if(!v)throw std::runtime_error(s);}
static unsigned crc7(unsigned c,unsigned b){return ((c<<1)^(((c>>6)^b)&1?9:0))&127;}
static unsigned crc16(unsigned c,unsigned b){return ((c<<1)^(((c>>15)^b)&1?0x1021:0))&65535;}
struct Card {
 uint64_t command=0;int bits=0;bool wide=false,bad_crc=false,no_response=false,bad_response_crc=false,wrong_command=false;
 std::deque<int> response,data;
 std::array<unsigned char,512> sector{};
 int rx=-1,write_bytes=512;std::array<unsigned,4> crc{},sent{};
 bool wrote=false;unsigned token=5;
 void packet(unsigned cmd,unsigned arg){
  if(no_response || cmd==0)return;
  if(wrong_command)cmd^=1;
  uint64_t p=(uint64_t(cmd)<<40)|(uint64_t(arg)<<8);unsigned c=0;
  for(int i=47;i>=8;--i)c=crc7(c,(p>>i)&1);
  p|=(c<<1)|1;if(bad_response_crc)p^=2;
  response.push_back(1);response.push_back(1);
  for(int i=47;i>=0;--i)response.push_back((p>>i)&1);
 }
 void got(){
  unsigned cmd=(command>>40)&63,arg=(command>>8)&0xffffffff;
  unsigned c=0;for(int i=47;i>=8;--i)c=crc7(c,(command>>i)&1);
  check((command&255)==((c<<1)|1),"command CRC7");
  if(cmd==2){
   response.push_back(1);response.push_back(1);c=0;
   for(int i=7;i>=0;--i)response.push_back((0x3f>>i)&1);
   for(int byte=0;byte<15;byte++)for(int i=7;i>=0;--i){int b=((0xa0+byte)>>i)&1;response.push_back(b);c=crc7(c,b);}
   for(int i=6;i>=0;--i)response.push_back((c>>i)&1);response.push_back(1);
  }else packet(cmd,cmd==8?arg:0x900);
  if(cmd==17 || cmd==51){
   int size=cmd==51?8:512;
   for(int i=0;i<60;i++)data.push_back(15);
   data.push_back(wide?0:14);crc.fill(0);
   for(int n=0;n<size;n++){
    int units=wide?2:8;
    for(int j=0;j<units;j++){
     unsigned nib=wide?(sector[n]>>(4*(1-j)))&15:14|((sector[n]>>(7-j))&1);
     data.push_back(nib);
     for(int l=0;l<(wide?4:1);l++)crc[l]=crc16(crc[l],(nib>>l)&1);
    }
   }
   if(bad_crc)crc[wide?3:0]^=1;
   for(int i=15;i>=0;i--){unsigned v=wide?0:14;for(int l=0;l<(wide?4:1);l++)v|=((crc[l]>>i)&1)<<l;data.push_back(v);}
   data.push_back(15);
  }
  if(cmd==24){rx=0;crc.fill(0);sent.fill(0);wrote=false;}
 }
 void rise(Vor_sd_native &d){
  if(!d.sd_cmd_t){if(bits || !d.sd_cmd_o){command=(command<<1)|d.sd_cmd_o;if(++bits==48){got();bits=0;}}}
  if(rx>=0 && !d.sd_dat_t){
   if(rx==0){check(d.sd_dat_o==(wide?0:14),"write start");rx=1;return;}
   int units=wide?2:8,total=write_bytes*units;
   if(rx<=total){
    int pos=(rx-1)/units;
    sector[pos]=(sector[pos]<<(wide?4:1))|(d.sd_dat_o&(wide?15:1));
    for(int l=0;l<(wide?4:1);l++)crc[l]=crc16(crc[l],(d.sd_dat_o>>l)&1);
   }else if(rx<=total+16){for(int l=0;l<(wide?4:1);l++)sent[l]=(sent[l]<<1)|((d.sd_dat_o>>l)&1);}
   else {
    check(d.sd_dat_o==15,"write end");for(int l=0;l<(wide?4:1);l++)check(crc[l]==sent[l],"write CRC16");
    data.push_back(15);data.push_back(15);
    for(int i=4;i>=0;i--)data.push_back(14|((token>>i)&1));
    for(int i=0;i<12;i++)data.push_back(14);data.push_back(15);wrote=true;rx=-2;return;
   }
   rx++;
  }
 }
 void fall(Vor_sd_native &d){
  d.sd_cmd_i=response.empty()?1:response.front();if(!response.empty())response.pop_front();
  d.sd_dat_i=data.empty()?15:data.front();if(!data.empty())data.pop_front();
 }
};
int main(int argc,char **argv){
 try{
 Verilated::commandArgs(argc,argv);Vor_sd_native d;Card c;uint64_t cycles=0;
 unsigned input_delay=argc>1?std::stoul(argv[1]):0,remaining=0,pending_cmd=1,pending_dat=15;
 check(input_delay<=2,"test supports up to 20ns return delay");
 auto tick=[&](){bool prev=d.sd_clk;d.clk=0;d.eval();d.clk=1;d.eval();++cycles;
   if(remaining && --remaining==0){d.sd_cmd_i=pending_cmd;d.sd_dat_i=pending_dat;}
   if(!prev && d.sd_clk)c.rise(d);
   if(prev && !d.sd_clk){
    unsigned old_cmd=d.sd_cmd_i,old_dat=d.sd_dat_i;c.fall(d);
    if(input_delay){pending_cmd=d.sd_cmd_i;pending_dat=d.sd_dat_i;
     d.sd_cmd_i=old_cmd;d.sd_dat_i=old_dat;remaining=input_delay;}
   }d.eval();};
 d.reset_n=0;d.sd_cmd_i=1;d.sd_dat_i=15;d.start=0;d.buffer_we=0;
 for(int i=0;i<5;i++)tick();d.reset_n=1;
 auto run=[&](unsigned cmd,unsigned arg,bool data,bool write,int bytes=512,int type=1){
  d.command=cmd;d.argument=arg;d.data_present=data;d.data_write=write;d.data_bytes=bytes;
  d.response_type=type;d.check_crc=1;d.four_bit=c.wide;d.half_period=2;d.start=1;tick();d.start=0;
  unsigned n=0;do{tick();check(++n<250000,"host transaction hung");}while(!d.done);
 };
 run(8,0x1aa,false,false);check(!d.error && d.response[0]==0x1aa,"R7");
 c.bad_response_crc=true;run(8,0x1aa,false,false);check(d.error==2,"bad response CRC accepted");c.bad_response_crc=false;
 c.wrong_command=true;run(8,0x1aa,false,false);check(d.error==2,"wrong response command accepted");c.wrong_command=false;
 run(8,0x1aa,false,false);check(!d.error,"recovery after bad response");
 run(2,0,false,false,0,2);check(!d.error && d.response[3]==0xa0a1a2a3,"R2");
 for(bool wide:{false,true}){
  c.wide=wide;
  for(int i=0;i<512;i++)c.sector[i]=(i*37+19)&255;
  run(17,2048,true,false);check(!d.error,"read result");
  for(int i=0;i<512;i++){d.buffer_address=i;d.eval();check(d.buffer_rdata==c.sector[i],"read payload");}
  run(51,0,true,false,8);check(!d.error,"SCR read");
  for(int i=0;i<512;i++){d.buffer_address=i;d.buffer_wdata=(i*17+71)&255;d.buffer_we=1;tick();}d.buffer_we=0;
  run(24,8192,true,true);check(!d.error && c.wrote,"write result");
  for(int i=0;i<512;i++)check(c.sector[i]==((i*17+71)&255),"write payload");
  c.bad_crc=true;run(17,2048,true,false);check(d.error==3,"bad read CRC accepted");c.bad_crc=false;
 }
 c.token=0xb;run(24,0,true,true);check(d.error==3,"write CRC rejection ignored");
 c.no_response=true;run(8,0x1aa,false,false);check(d.error==1,"missing card timeout");
 std::cout<<"PASS native SD R7/R2, 1/4-bit 512-byte read/write, SCR, CRC errors, write reject, timeout input_delay_ns="<<input_delay*10<<" cycles="<<cycles<<"\n";
 }catch(const std::exception &e){std::cerr<<"FAIL "<<e.what()<<"\n";return 1;}
}

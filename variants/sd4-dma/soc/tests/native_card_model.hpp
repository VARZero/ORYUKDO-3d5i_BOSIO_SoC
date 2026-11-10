#pragma once
#include <array>
#include <deque>
#include <map>
#include <stdexcept>
static void check(bool v,const char *s){if(!v)throw std::runtime_error(s);}
static unsigned crc7(unsigned c,unsigned b){return ((c<<1)^(((c>>6)^b)&1?9:0))&127;}
static unsigned crc16(unsigned c,unsigned b){return ((c<<1)^(((c>>15)^b)&1?0x1021:0))&65535;}
struct Card {
 uint64_t command=0;int bits=0;bool wide=false,bad_crc=false,no_response=false;
 std::deque<int> response,data;
 std::array<unsigned char,512> sector{};
 int rx=-1,write_bytes=512;std::map<unsigned,std::array<unsigned char,512>> disk;unsigned write_lba=0;bool app=false;std::array<unsigned,4> crc{},sent{};
 bool wrote=false;unsigned token=5;
 void packet(unsigned cmd,unsigned arg){
  if(no_response || cmd==0)return;
  uint64_t p=(uint64_t(cmd)<<40)|(uint64_t(arg)<<8);unsigned c=0;
  for(int i=47;i>=8;--i)c=crc7(c,(p>>i)&1);
  p|=(c<<1)|1;
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
  }else packet(cmd,cmd==8?arg:cmd==41?0xc0ff8000:cmd==3?0x12340900:0x900);
  if(cmd==6 && app && arg==2)wide=true;
  app=cmd==55;
  if(cmd==17 && disk.count(arg))sector=disk[arg];
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
  if(cmd==24){write_lba=arg;rx=0;crc.fill(0);sent.fill(0);wrote=false;}
 }
 template<class DUT> void rise(DUT &d){
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
    for(int i=0;i<12;i++)data.push_back(14);data.push_back(15);wrote=true;disk[write_lba]=sector;rx=-2;return;
   }
   rx++;
  }
 }
 template<class DUT> void fall(DUT &d){
  d.sd_cmd_i=response.empty()?1:response.front();if(!response.empty())response.pop_front();
  d.sd_dat_i=data.empty()?15:data.front();if(!data.empty())data.pop_front();
 }
};

#include "Vtb_cpu_storage.h"
#include <verilated.h>
#include <memory>
#include "native_card_model.hpp"
int main(int argc,char**argv){
 auto c=std::make_unique<VerilatedContext>();c->commandArgs(argc,argv);c->threads(1);
 auto m=std::make_unique<Vtb_cpu_storage>(c.get());
 Card card;for(int i=0;i<512;i++)card.disk[4096][i]=(i*29+11)&255;
 m->sd_cmd_i=1;m->sd_dat_i=15;
 m->cpu_clk=0;m->fabric_clk=0;m->reset_n=0;m->eval();
 for(unsigned long long t=5;t<50000000&&!c->gotFinish();t+=5){
  c->time(t*1000);m->fabric_clk=!m->fabric_clk;if(t%10==0)m->cpu_clk=!m->cpu_clk;
  bool previous=m->sd_clk;m->reset_n=t>=200;m->eval();
  if(!previous&&m->sd_clk)card.rise(*m);if(previous&&!m->sd_clk)card.fall(*m);m->eval();
 }m->final();return c->gotFinish()?0:1;
}

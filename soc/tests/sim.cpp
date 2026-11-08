#include "Vtb_gen3_bosio.h"
#include "verilated.h"
#include <memory>
int main(int argc,char**argv){
 auto c=std::make_unique<VerilatedContext>(); c->commandArgs(argc,argv);c->threads(1);
 auto m=std::make_unique<Vtb_gen3_bosio>(c.get());
 m->cpu_clk=0;m->fabric_clk=0;m->reset_n=0;m->eval();
 for(unsigned long long t=5;t<60000000 && !c->gotFinish();t+=5){
  c->time(t*1000);m->fabric_clk=!m->fabric_clk;
  if(t%10==0)m->cpu_clk=!m->cpu_clk;
  m->reset_n=t>=200;m->eval();
 }
 m->final();return c->gotFinish()?0:1;
}

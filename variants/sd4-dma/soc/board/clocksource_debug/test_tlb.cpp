#include "Vrv32_sv32.h"
#include <map>
#include <iostream>
#include <stdexcept>
struct Bench {
 Vrv32_sv32 d; std::map<unsigned,unsigned> mem; bool pending=false; unsigned due=0,reply=0,cycles=0,requests=0; bool busfault=false;
 void tick(){d.clk=0;d.request_ready=!pending;d.response_valid=pending&&cycles>=due;d.response_data=reply;d.response_fault=busfault;d.eval();
  bool consume=d.response_valid&&d.response_ready;bool accept=d.request_valid&&d.request_ready;
  if(accept){reply=mem[d.request_address];pending=true;due=cycles+3;requests++;}
  if(consume)pending=false; d.clk=1;d.eval();cycles++;
 }
 void fence(){d.flush=1;tick();d.flush=0;tick();}
 Bench(){d.reset_n=0;d.valid=0;d.result_ready=0;d.flush=0;d.sum=0;d.mxr=0;d.privilege=1;d.access_type=1;d.satp=0x80000020;for(int i=0;i<4;i++)tick();d.reset_n=1;tick();}
 void start(unsigned va){while(!d.ready)tick();d.virtual_address=va;d.valid=1;tick();d.valid=0;}
 unsigned finish(bool fault=false,unsigned cause=0){for(int i=0;!d.result_valid&&i<100;i++)tick();if(!d.result_valid||bool(d.fault)!=fault||(fault&&d.cause!=cause))throw std::runtime_error("translation result/fault");unsigned pa=d.physical_address;d.result_ready=1;tick();d.result_ready=0;return pa;}
 unsigned translate(unsigned va,bool fault=false,unsigned cause=0){start(va);return finish(fault,cause);}
};
void check(bool b,const char*s){if(!b)throw std::runtime_error(s);}
unsigned pte(unsigned pa,unsigned flags){return (pa>>12<<10)|flags;}
int main()try{
 Bench b;constexpr unsigned va=0x40001234;unsigned root=0x20400,leaf=0x21004;
 b.mem[root]=pte(0x21000,1);b.mem[leaf]=pte(0x81234000,0xcf);
 check(b.translate(va)==0x81234234,"cold translation");check(b.requests==2,"cold walk count");unsigned n=b.requests;
 check(b.translate(va+4)==0x81234238&&b.requests==n,"TLB hit");
 b.mem[leaf]=pte(0x82345000,0xcf);check(b.translate(va)==0x81234234,"cached mapping before fence");b.fence();check(b.translate(va)==0x82345234&&b.requests==n+2,"fence remap");
 b.d.access_type=2;check(b.translate(va)==0x82345234,"store context miss");b.mem[leaf]=pte(0x82345000,0x4b);b.fence();b.translate(va,true,15);
 b.d.access_type=1;b.mem[leaf]=pte(0x82345000,0x49);b.fence();b.d.mxr=1;check(b.translate(va)==0x82345234,"MXR execute read");b.d.mxr=0;b.translate(va,true,13);
 b.mem[leaf]=pte(0x82345000,0xdf);b.fence();b.d.sum=1;check(b.translate(va)==0x82345234,"SUM user page read");b.d.sum=0;b.translate(va,true,13);
 b.d.privilege=0;check(b.translate(va)==0x82345234,"U user page");b.d.privilege=1;b.d.access_type=0;b.d.sum=1;b.translate(va,true,12);
 b.d.access_type=1;b.d.sum=0;b.mem[leaf]=pte(0x82345000,0xcf);b.fence();check(b.translate(va)==0x82345234,"baseline context");
 b.d.satp=0x80000022;b.mem[0x22400]=pte(0x23000,1);b.mem[0x23004]=pte(0x83456000,0xcf);check(b.translate(va)==0x83456234,"SATP context");
 b.d.privilege=3;check(b.translate(va)==va,"M bare");b.d.privilege=1;b.d.satp=0;check(b.translate(va)==va,"satp bare");
 b.d.satp=0x80000020;b.mem[root]=pte(0x84000000,0xcf);b.fence();check(b.translate(0x403ab678)==0x843ab678,"superpage");b.mem[root]=pte(0x84001000,0xcf);b.fence();b.translate(va,true,13);
 b.mem[root]=pte(0x21000,1);b.mem[leaf]=pte(0x81234000,0xcf);b.fence();b.start(va);while(!b.pending)b.tick();
 b.mem[root]=pte(0x23000,1);b.mem[0x23004]=pte(0x84567000,0xcf);b.fence();check(b.finish()==0x84567234,"flush drains and restarts old root read");
 n=b.requests;check(b.translate(va)==0x84567234&&b.requests==n,"fresh refill after restart");
 b.fence();b.start(va);while(!b.d.result_valid)b.tick();b.mem[0x23004]=pte(0x85678000,0xcf);b.fence();check(b.finish()==0x85678234,"flush held result restarts");
 b.d.satp=0x80300000;b.start(va);b.fence();b.finish(true,5);
 b.d.satp=0x80000020;b.mem[root]=pte(0x23000,1);b.mem[0x23004]=0xc00000cf;b.fence();b.translate(va,true,5);
 b.mem[0x23004]=pte(0x85678000,0xcf);b.fence();b.busfault=true;b.translate(va,true,5);b.busfault=false;
 for(unsigned i=0;i<128;i++){unsigned v=0x40000000+((i%16)<<12)+(i*4%4096);b.mem[0x23000+((v>>12)&1023)*4]=pte(0x88000000+(i<<12),0xcf);b.fence();unsigned want=0x88000000+(i<<12)+(v&4095);check(b.translate(v)==want,"mapping stress");n=b.requests;check(b.translate(v)==want&&b.requests==n,"stress hit");}
 std::cout<<"PASS TLB context/permission/fence/inflight/large-page/PA-range and 128 remaps; requests="<<b.requests<<" cycles="<<b.cycles<<"\n";
}catch(const std::exception&e){std::cerr<<"FAIL "<<e.what()<<"\n";return 1;}

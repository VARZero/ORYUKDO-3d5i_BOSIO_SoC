// Cold reset -> synthesizable SPI loader -> one persistent native DDR model ->
// production CPU/CDC/AXI/MIG bridge -> pin-level UART Linux shell.
#include "Vsd_boot.h"
#include "Vtb_kfb_coldboot.h"
#include "sd_card_model.hpp"
#include <sys/mman.h>
#include <chrono>
#include <cstring>
#include <set>

struct NativeMemory {
    struct Command {bool write; uint32_t address;};
    struct Data {std::array<uint32_t,8> words; uint32_t mask;};
    struct Read {uint64_t due; std::array<uint32_t,8> words;};
    uint8_t *ram;
    std::deque<Command> commands;
    std::deque<Data> data;
    std::deque<Read> reads;
    uint64_t writes=0,read_count=0,clear_count=0,clock=0;
    bool boot=true;
    std::set<uint32_t> patterns,checked;
    NativeMemory() {
        ram=static_cast<uint8_t*>(mmap(nullptr,1ULL<<30,PROT_READ|PROT_WRITE,
                     MAP_PRIVATE|MAP_ANONYMOUS,-1,0));
        require(ram!=MAP_FAILED,"DDR allocation");
        // Poison all RAM: only the real SD loader can initialize it.
        std::memset(ram,0xa5,1ULL<<30);
    }
    bool ready() const {return commands.size()<16 && clock%11!=3;}
    bool wready() const {return data.size()<16 && clock%7!=1;}
    bool valid() const {return !reads.empty() && reads.front().due<=clock;}
    template<class T> void drive(T &d) {
        d.app_rdy=ready();d.app_wdf_rdy=wready();d.rd_valid=valid();
        if(valid()) for(int i=0;i<8;i++) d.rd_data[i]=reads.front().words[i];
    }
    void edge(bool en,unsigned cmd,uint32_t addr,bool wen,bool end,const uint32_t *w,uint32_t mask) {
        if(valid()) reads.pop_front();
        if(en && ready()) {
            require(cmd<=1 && !(addr&7) && uint64_t(addr)*4+32<=(1ULL<<30),"MIG command/address");
            commands.push_back({cmd==0,addr*4});
        }
        if(wen && wready()) {
            require(end,"MIG BL8 WDF end");
            Data d;std::copy_n(w,8,d.words.begin());d.mask=mask;data.push_back(d);
        }
        if(!commands.empty() && (!commands.front().write || !data.empty())) {
            auto c=commands.front();commands.pop_front();
            if(c.write) {
                auto v=data.front();data.pop_front();++writes;
                if(boot && clear_count<(1ULL<<25)) {
                    require(c.address==clear_count*32 && v.mask==0,"Full DDR clear order/mask");
                    for(auto word:v.words) require(word==0,"Full DDR clear data");
                    ++clear_count;
                }
                for(unsigned i=0;i<32;i++) if(!(v.mask&(1u<<i)))
                    ram[c.address+i]=uint8_t(v.words[i/4]>>(8*(i%4)));
                if(!boot && c.address>=0x08000000 && !(c.address&4095) && !(v.mask&15)) {
                    uint32_t value;std::memcpy(&value,ram+c.address,4);
                    if((value^0x39a7f184u)<40960) patterns.insert(c.address);
                }
            } else {
                Read r{clock+5+clock%5,{}};
                std::memcpy(r.words.data(),ram+c.address,32);
                reads.push_back(r);++read_count;
                if(!boot && patterns.count(c.address) && (r.words[0]^0x39a7f184u)<40960)
                    checked.insert(c.address);
            }
        }
        ++clock;
    }
    bool empty() const {return commands.empty()&&data.empty()&&reads.empty();}
};

struct Uart {
    std::string input,window;
    unsigned send_tick=0,send_bit=0,sample=0,bit=0,stage=0;
    uint8_t byte=0;bool previous=true,success=false;
    bool rx() const {return input.empty() || ((((unsigned(uint8_t(input[0]))<<1)|0x200)>>send_bit)&1);}
    void edge(bool tx) {
        if(!input.empty() && ++send_tick==434) {
            send_tick=0;if(++send_bit==10){send_bit=0;input.erase(0,1);}
        }
        if(!sample && previous && !tx){sample=216;bit=0;byte=0;}
        else if(sample && --sample==0) {
            if(!bit)require(!tx,"UART start bit");
            if(bit>0 && bit<9 && tx) byte|=1u<<(bit-1);
            if(bit++<9)sample=432;
            else {
                require(tx,"UART stop bit");char c=char(byte);std::cout.put(c).flush();
                if(c!='\r')window+=c;
                if(window.size()>4096)window.erase(0,1024);
                require(window.find("Kernel panic")==std::string::npos,"Linux kernel panic");
                if(stage==0 && window.ends_with("oryukdo# ")) {
                    input="echo $((19+23))\r";stage=1;window.clear();
                } else if(stage==1 && window.find("\n42\n")!=std::string::npos && window.ends_with("oryukdo# ")) {
                    input="uname -r\r";stage=2;window.clear();
                } else if(stage==2 && window.find("6.12.0-oryukdo-kfb")!=std::string::npos && window.ends_with("oryukdo# ")) {
                    input="grep MemTotal /proc/meminfo\r";stage=3;window.clear();
                } else if(stage==3 && window.find("MemTotal:")!=std::string::npos && window.ends_with("oryukdo# ")) {
                    input="ddrcheck\r";stage=4;window.clear();
                } else if(stage==4 && window.find("DDR_HIGH_OK pages=16")!=std::string::npos && window.ends_with("oryukdo# ")) success=true;
            }
        }
        previous=tx;
    }
};

int main(int argc,char **argv) try {
    require(argc>=2,"usage: Vtb_kfb_coldboot release.img [max CPU cycles]");
    const uint64_t limit=argc>2?std::stoull(argv[2]):4000000000ULL;
    NativeMemory memory;Card card(read_file(argv[1]),"good");
    auto start=std::chrono::steady_clock::now();
    auto seconds=[&](){return std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();};
    Vsd_boot sd;
    // CPU stays in its power-on/reset state during SD loading. We do not evaluate
    // its reset-only clocks for hundreds of millions of loader cycles. No CPU
    // architectural state is restored, patched, or carried from another run.
    uint64_t boot_cycle=0;
    std::cout<<"START cold boot: poisoned 1GiB DDR, SD image is the only payload source\n"<<std::flush;
    for(;boot_cycle<1000000000ULL;boot_cycle++) {
        sd.clk=0;sd.reset=boot_cycle<8;sd.calibrated=boot_cycle>=24;
        memory.drive(sd);sd.eval();
        memory.edge(sd.en,sd.write_cmd?0:1,sd.addr,sd.wdf_en,sd.wdf_en,sd.wdata,0);
        sd.clk=1;sd.eval();sd.sd_miso=card.advance(sd.sd_ncs,sd.sd_dclk,sd.sd_mosi);
        require(!sd.failed,"SD boot loader failed");
        if(sd.done)break;
        if(boot_cycle && boot_cycle%50000000==0)
            std::cout<<"[SD cycles="<<boot_cycle<<" clear="<<memory.clear_count<<" sectors="<<card.reads<<" seconds="<<seconds()<<"]\n"<<std::flush;
    }
    require(sd.done && memory.empty() && memory.clear_count==(1ULL<<25),"SD/DDR handoff incomplete");
    // Independent byte comparison against sectors; never used to fill memory.
    size_t payload=2049*512;const unsigned offsets[]={0,0x400000,0x7f00000};
    for(unsigned i=0;i<3;i++) {
        uint32_t count;std::memcpy(&count,card.image.data()+2048*512+8+8*i,4);
        require(payload+size_t(count)*512<=card.image.size(),"segment bounds");
        require(!std::memcmp(memory.ram+offsets[i],card.image.data()+payload,size_t(count)*512),"loaded payload differs from SD");
        payload+=size_t(count)*512;
    }
    std::cout<<"PASS SD_LOAD cold cycles="<<boot_cycle<<" clear_lines="<<memory.clear_count<<" sectors="<<card.reads<<" seconds="<<seconds()<<"\n"<<std::flush;
    memory.boot=false;
    Vtb_kfb_coldboot d;Uart uart;
    d.boot_done=1;d.boot_bad=0;d.boot_en=0;d.boot_wr=0;d.boot_wen=0;
    d.boot_addr=0;for(int i=0;i<8;i++)d.boot_data[i]=0;
    d.calib=1;d.clocks_locked=1;d.rd_end=1;
    unsigned pixel_phase=0,trap_prints=12;uint64_t retires=0;
    uint32_t pc=0;bool first_retire=true;
    for(uint64_t ui=0;ui<2*limit;ui++) {
        d.ui_clk=0;d.rst_n=ui>=32;d.ui_rst=ui<32;d.uart_rx=uart.rx();
        memory.drive(d);d.eval();
        memory.edge(d.app_en,d.app_cmd,d.app_addr,d.app_wdf_wren,d.app_wdf_end,d.app_wdf_data,d.app_wdf_mask);
        bool rising=(ui&1)==0;
        if(rising && d.debug_retire) {
            pc=d.debug_pc;++retires;
            if(first_retire){require(pc==0,"CPU must cold-start at reset ROM PC 0");first_retire=false;}
        }
        if(rising && d.debug_trap && trap_prints) {
            std::cout<<"[trap cause="<<unsigned(d.debug_cause)<<" pc="<<std::hex<<d.debug_trap_pc<<std::dec<<"]\n";--trap_prints;
        }
        d.ui_clk=1;d.cpu_clk=rising;
        pixel_phase+=14850;if(pixel_phase>=20000){pixel_phase-=20000;d.pixel_clk=!d.pixel_clk;}
        d.eval();
        if(rising)uart.edge(d.uart_tx);
        d.ui_clk=0;
        pixel_phase+=14850;if(pixel_phase>=20000){pixel_phase-=20000;d.pixel_clk=!d.pixel_clk;}
        d.eval();
        if(uart.success) {
            require(memory.checked.size()>=16,"independent native DDR high-page readback coverage");
            std::cout<<"\nPASS COLD_SD_LINUX_SHELL cpu_cycles="<<ui/2<<" sd_cycles="<<boot_cycle
                <<" retires="<<retires<<" high_pages="<<memory.checked.size()<<" seconds="<<seconds()
                <<" first_pa=0x"<<std::hex<<(*memory.checked.begin()+0x80000000u)<<std::dec<<"\n";return 0;
        }
        if(ui && ui%2000000==0)
            std::cout<<"[CPU cycles="<<ui/2<<" retires="<<retires<<" pc=0x"<<std::hex<<pc<<" satp=0x"<<d.debug_satp<<std::dec
                <<" stage="<<uart.stage<<" seconds="<<seconds()<<"]\n"<<std::flush;
    }
    throw std::runtime_error("cold Linux UART timeout");
} catch(const std::exception &e) {std::cerr<<"FAIL COLD_BOOT "<<e.what()<<"\n";return 1;}

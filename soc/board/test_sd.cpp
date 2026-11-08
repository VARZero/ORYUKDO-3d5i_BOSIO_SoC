// Pin-level SPI card and native MIG interface model for the synthesizable loader.
#include "Vsd_boot.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using Bytes = std::vector<uint8_t>;
static void require(bool ok, const char* why) {
    if (!ok) throw std::runtime_error(why);
}
static Bytes read_file(const std::string& name) {
    std::ifstream input(name, std::ios::binary);
    if (!input) throw std::runtime_error("cannot open " + name);
    return Bytes(std::istreambuf_iterator<char>(input), {});
}
static uint16_t crc16(const uint8_t* p) {
    uint16_t crc = 0;
    for (int n = 0; n < 512; ++n) {
        crc ^= uint16_t(p[n]) << 8;
        for (int b = 0; b < 8; ++b) crc = (crc << 1) ^ ((crc & 0x8000) ? 0x1021 : 0);
    }
    return crc;
}
class Card {
public:
    Bytes image;
    std::string fault;
    unsigned reads=0, idle_clocks=0, init_attempts=0;
    Card(Bytes bytes, const std::string& mode) : image(std::move(bytes)), fault(mode) {}
    bool advance(bool cs, bool clk, bool mosi) {
        if (cs) {
            if (clk && !last_clk) ++idle_clocks;
            bits=0; receiving=0; outgoing=0xff; command.clear(); queue.clear();
        } else if (clk && !last_clk) {
            receiving=(receiving<<1) | mosi;
            if (++bits==8) {
                if (!command.empty() || (receiving & 0xc0)==0x40) command.push_back(receiving);
                if (command.size()==6) { respond(); command.clear(); }
                bits=0; receiving=0;
            }
        } else if (!clk && last_clk && bits==0) {
            outgoing=queue.empty() ? 0xff : queue.front();
            if (!queue.empty()) queue.pop_front();
        }
        last_clk=clk;
        return cs || ((outgoing >> (7-bits)) & 1);
    }
private:
    Bytes command;
    std::deque<uint8_t> queue;
    unsigned bits=0;
    uint8_t receiving=0, outgoing=0xff;
    bool last_clk=false, prefixed=false, active=false;
    void respond() {
        const uint8_t cmd=command[0] & 63;
        uint32_t arg=0;
        for (int i=1; i<=4; ++i) arg=(arg<<8)|command[i];
        queue.push_back(0xff); // delayed R1
        if (fault=="no-card") return;
        switch(cmd) {
        case 0:
            require(idle_clocks>=74 && arg==0 && command[5]==0x95,"CMD0 or power-up clock count");
            queue.push_back(1); break;
        case 8:
            require(arg==0x1aa && command[5]==0x87,"CMD8 frame");
            queue.insert(queue.end(), {1,0,0,1,0xaa}); break;
        case 55: prefixed=true; queue.push_back(1); break;
        case 41:
            require(prefixed && arg==0x40000000,"ACMD41 sequence");
            prefixed=false; active=++init_attempts>=3; queue.push_back(active ? 0 : 1); break;
        case 58:
            require(active,"card not ready");
            queue.insert(queue.end(), {0,uint8_t(fault=="sdsc" ? 0x80 : 0xc0),0xff,0x80,0}); break;
        case 17: {
            require(active && arg==2048+reads && uint64_t(arg+1)*512<=image.size(),"read LBA");
            ++reads;
            auto p=image.data()+size_t(arg)*512;
            uint16_t crc=crc16(p);
            if (fault=="sector-crc" && reads==2) crc^=1;
            queue.insert(queue.end(), {0,0xff,0xff,0xfe});
            queue.insert(queue.end(),p,p+512);
            queue.push_back(crc>>8); queue.push_back(crc);
            break;
        }
        default: throw std::runtime_error("unexpected card command "+std::to_string(cmd));
        }
    }
};
int main(int argc,char** argv) try {
    require(argc==6 || argc==7,"usage: test image fw kernel dtb mode [DDR.hex]");
    std::ofstream snapshot;
    if(argc==7) { snapshot.open(argv[6]); require(bool(snapshot),"cannot open DDR image"); }
    std::string mode=argv[5];
    Card card(read_file(argv[1]),mode);
    std::array<Bytes,3> expected={read_file(argv[2]),read_file(argv[3]),read_file(argv[4])};
    for (auto& bytes:expected) bytes.resize((bytes.size()+511)/512*512);
    if (mode=="header") card.image.at(2048*512)^=1;
    if (mode=="oversize") std::fill_n(card.image.begin()+2048*512+8,4,0xff);
    if (mode=="payload-crc") card.image.at(2048*512+12)^=1;
    constexpr unsigned bases[]={0,0x100000,0x1fc0000};
    constexpr unsigned clear_lines=1024*1024*1024/32;
    unsigned clears=0, segment=0, offset=0, writes=0, reads=0, delay=0;
    uint32_t last_addr=0;
    std::array<uint32_t,8> last_data{};
    bool pending=false, have_write=false;
    Vsd_boot dut;
    dut.clk=0; dut.reset=1; dut.calibrated=0; dut.sd_miso=1;
    dut.rd_valid=0; dut.app_rdy=0; dut.app_wdf_rdy=0;
    // The readiness patterns differ for data and command. Each read response is delayed.
    for (uint64_t cycle=0; cycle<1000000000; ++cycle) {
        dut.clk=0; dut.reset=cycle<8; dut.calibrated=cycle>=24;
        dut.app_rdy=(cycle%7)!=1; dut.app_wdf_rdy=(cycle%5)!=0;
        dut.rd_valid=pending && delay==0;
        if (dut.rd_valid) for (int i=0;i<8;i++) dut.rd_data[i]=last_data[i]^(mode=="ddr" && i==6);
        dut.eval();
        if (pending && delay) --delay;
        if (dut.rd_valid) pending=false;
        if (dut.en && dut.app_rdy) {
            if (dut.write_cmd) {
                require(dut.calibrated && dut.wdf_en && dut.app_wdf_rdy,"unpaired native write");
                if (clears<clear_lines) {
                    require(dut.addr==clears*8,"DDR clear address");
                    for (int i=0;i<8;i++) require(dut.wdata[i]==0,"DDR clear data");
                    ++clears;
                } else {
                    require(segment<3 && !have_write && !pending,"excess or overlapping write");
                    require(dut.addr==bases[segment]+offset/4,"payload DDR address");
                    for (int i=0;i<8;i++) {
                        last_data[i]=dut.wdata[i];
                        for(int j=0;j<4;j++) require(uint8_t(last_data[i]>>(8*j))==expected[segment][offset+4*i+j],"payload data");
                    }
                    if (snapshot.is_open()) {
                        if (offset==0) snapshot<<"@"<<std::hex<<dut.addr<<"\n";
                        for (auto word:last_data) snapshot<<std::hex<<std::setfill('0')<<std::setw(8)<<word<<"\n";
                    }
                    offset+=32; ++writes; have_write=true; last_addr=dut.addr;
                    if(offset==expected[segment].size()) { ++segment; offset=0; }
                }
            } else {
                require(have_write && dut.addr==last_addr && !pending,"readback address or order");
                have_write=false; pending=true; delay=2+cycle%7; ++reads;
            }
        }
        dut.clk=1; dut.eval();
        dut.sd_miso=card.advance(dut.sd_ncs,dut.sd_dclk,dut.sd_mosi);
        if (dut.done || dut.failed) {
            bool success=mode=="good";
            require(bool(dut.done)==success && bool(dut.failed)!=success,"unexpected terminal state");
            require(clears==clear_lines && (!success || (segment==3 && writes==reads && !pending && !have_write)),"incomplete DDR");
            if(mode=="header" || mode=="oversize" || mode=="sdsc" || mode=="no-card") require(writes==0,"unexpected payload write");
            if(mode=="ddr") require(reads==1,"DDR fault did not stop loader");
            if(mode=="payload-crc") require(segment==1 && offset==0,"segment CRC fault boundary");
            if(mode=="sector-crc") require(writes==16 && card.reads==2,"sector CRC fault boundary");
            for(int i=0;i<128;i++) {
                dut.clk=0; dut.eval(); dut.clk=1; dut.eval();
                require(!dut.en && bool(dut.done)==success && bool(dut.failed)!=success,"terminal state not stable");
            }
            std::cout<<"PASS "<<mode<<" cycles="<<cycle<<" clear_lines="<<clears<<" sectors="<<card.reads
                     <<" payload_lines="<<writes<<" readbacks="<<reads<<" cpu_release="<<int(dut.done)<<"\n";
            return 0;
        }
    }
    throw std::runtime_error("loader timeout");
} catch(const std::exception& e) { std::cerr<<"FAIL "<<e.what()<<"\n"; return 1; }

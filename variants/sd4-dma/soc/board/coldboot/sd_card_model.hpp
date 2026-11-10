#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <fstream>
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

# ORYUKDO: native 4비트 SD / DMA / 영구 파일시스템 작업본

기존 `work/bosio-linux-sw`를 보존하고 만든 별도 작업본이다. 보드에는 접근하지 않았다.
이 디렉터리는 기존 검증본을 대체하는 정식 릴리스가 아니다. 아래 검증 범위를 구분해야 한다.

공개 저장소에서는 `variants/sd4-dma/`가 이 작업본의 루트다. 통합 안내는 저장소의
[구조](../../docs/구조.md), [소스 구성](../../docs/소스_구성.md), [빌드](../../docs/빌드.md),
[검증](../../docs/검증.md), [보드 사용](../../docs/보드_사용.md)을 따른다.
파일은 [SD4 사전 릴리스](https://github.com/VARZero/ORYUKDO-3d5i_BOSIO_SoC/releases/tag/sd4-dma-20261110-candidate)에 공개했다.
릴리스 압축본은 검증 시점으로 고정돼 있으며 문서의 최신 내용은 `main`을 기준으로 한다.
이 문서의 로컬 절대 경로는 당시 실행 위치이고, 다른 PC에서 자동 생성되는 경로가 아니다.

## 적용한 구조

* SD CLK=B20, CMD=E17, DAT0=A20, DAT1=B21, DAT2=F16, DAT3=A21. BANK16, LVCMOS33.
* 전원 인가부터 native SD로 초기화한다. SPI 부팅 후 native 모드로 전환하지 않는다.
* 초기화 400kHz, 전송 목표 25MHz. 1비트 초기화 및 4비트 전송, SDHC/SDXC 블록 주소 사용.
* `sd_boot`는 기존 부팅 헤더, DDR 주소, CRC32 검증을 유지하고 카드 바이트 인터페이스만 분리했다.
* 부팅 완료 전에는 부트 로더가 SD/DDR을 소유한다. 완료 뒤 Linux MMC 호스트 드라이버가 같은 SD 호스트를 제어한다.
* Linux 런타임 SD 수신은 CRC 확인 후 DDR로 DMA 전송한다. 송신은 DDR에서 버퍼를 채운 뒤 SD 명령을 발행한다.
  전원 인가 직후의 raw 부팅은 기존 `sd_boot`의 바이트 입력·CRC32·DDR 기록 경로를 유지한다.
  이 부트 로더 경로까지 새 DMA로 대체한 것은 아니다.
* CPU 명령 DMA는 비중첩 메모리 복사와 고정 32비트 패턴 채우기를 지원한다. Linux DMAengine에는 memcpy/memset으로 등록한다.
* 기존 CPU + BOSIO 3개 AXI 마스터에 저장소 DMA 마스터를 추가했다. 64바이트 이하 INCR burst로 나누고 4KiB 경계를 넘지 않는다.
* DMA 쓰기도 CPU 원자적 접근 잠금과 예약 무효화 경로를 통과한다. 메모리 복사는 읽기를 끝낸 뒤 쓰기를 발행한다.
* PLIC 호환 2-source / hart0 M·S context를 추가했다. SD 완료=1, 복사 DMA 완료=2.
* CSR의 MEIP/SEIP 입력, 마스크, 위임 및 우선순위를 연결했다. 스케줄러 NEL/IST/PRM/FCL 알고리즘은 변경하지 않았다.
* MIG 및 HDMI IP 소스는 수정하지 않았다.

## 파일시스템과 소프트웨어

SD 이미지의 첫 파티션은 기존 `ORYSD001` raw 부팅 데이터다. 두 번째 파티션은 1MiB 경계에 정렬한 ext4이다.
기본 두 번째 파티션 용량은 256MiB이며 `make_image.py --data-mib`로 조절한다.
카드의 나머지 전체 용량으로 자동 확장하지 않는다. 초기 RAM 파일시스템과 BusyBox는 유지한다.
보존된 BoAYO native-v2 실행 파일도 초기 RAM 파일시스템에 남아 있으며 이번 작업은 BoAYO 렌더링을 변경하지 않는다.

Linux에서는 `/dev/mmcblk0p2`를 `/data`에 마운트하도록 초기화를 추가했다.
마운트 실패 시에도 UART 복구 셸을 제공한다. 실패한 `/data` 디렉터리에 쓴 파일은 영구 저장되지 않는다.
`storage-check`는 `/data`가 실제 ext4로 마운트됐는지 확인한 뒤 임시 파일 쓰기, sync, 캐시 비우기, 해시 비교를 실행한다.
이는 보드에서 실행할 검사이며 이미지 생성 시 수행됐다는 의미가 아니다.

## 레지스터

| 주소 | 기능 |
|---|---|
| 0x10008000 | SD 호스트, signature 0x53443431 |
| 0x10009000 | 메모리 복사/채우기 DMA |
| 0x0c000000 | PLIC, source 1=SD, 2=DMA |

SD offset: 0x04 argument, 0x08 command/start, 0x0c status/W1C done,
0x10 half-divider, 0x14 bus width, 0x18 DMA physical address, 0x1c data bytes,
0x20..0x2c response low-to-high, 0x30 IRQ enable.
Command bits: [5:0] opcode, [7:6] response (none/48/136/48+busy), [8] CRC check,
[9] data present, [10] write. Status: [0] busy, [1] done, [6:4] error.

DMA offset: 0x00 source, 0x04 destination, 0x08 bytes, 0x0c fill pattern,
0x10 command (1=copy, 2=fill, bit8 IRQ enable), 0x14 status (busy/done/error at bits 0/1/2).
Status bit1 is W1C. 주소와 길이는 4바이트 정렬이어야 한다. DMA는 DDR 범위만 허용한다.
Linux DMA API의 물리/DMA 주소를 사용하며 사용자 가상 주소를 하드웨어에 넣지 않는다.

## 검증과 재현

WSL에서 저장소 RTL 회귀 검증:

```sh
bash software/storage/test.sh
bash software/storage/test_cpu.sh
```

커널 및 이미지 빌드:

```sh
bash software/storage/build.sh /var/tmp/oryukdo-sd4-linux
```

현재 빌드 스크립트는 이 PC의 Linux 6.12 작업 소스와 기존 native-v2 root를 복사한다.
원본 Linux 트리와 원본 root를 덮어쓰지 않는다. 새로운 드라이버는 `software/storage/oryukdo_sd.c`,
`oryukdo_dma.c`이며 복사한 Linux 트리에만 추가한다.
재현에 쓰는 경로와 도구는 스크립트에 명시돼 있다. 다른 컴퓨터에서는 기준 Linux/root/toolchain 경로를 준비해야 한다.

새 RTL 결과의 근거는 `validation/`이다. 복사돼 온 다른 과거 리포트를 새 설계의 PASS 근거로 사용하면 안 된다.
테스트는 카드/DDR 모델을 사용하는 디지털 검증이며 실제 SD 카드, MIG PHY와 PCB의 동작 검증이 아니다.

이번 작업에서 발견하고 수정한 문제:

1. 512바이트 SD 버퍼의 여러 쓰기 지점 때문에 RAM 추론이 깨져 수천 개 FF와 LUT가 생성됐다.
   단일 읽기/쓰기 주소 경로로 정리해 저장소 OOC LUT가 9,236에서 1,604로 줄었다(IOB 추가 전 비교).
2. DMA 읽기 오류 뒤 AWVALID가 한 사이클 발행돼 버스가 오지 않는 쓰기 데이터를 기다릴 수 있었다.
   읽기 실패 시 쓰기 주소 발행을 막았고, 오류 다음의 정상 전송 및 768개 무작위 descriptor로 회귀 검증했다.
3. 기존 최소 Linux 설정은 CONFIG_BLOCK이 꺼져 있어 MMC_BLOCK/ext4가 단순 설정만으로 켜지지 않았다.
   BLOCK과 종속 기능을 함께 활성화하고 최종 .config에서 확인했다.
4. 소프트웨어 타임아웃으로 격리한 SD 호스트에는 set_ios도 레지스터를 쓰지 않도록 했다.
5. 카드 입력에서 CRC 판정까지 한 번에 처리하던 경로를 IOB 입력 레지스터와 다음 클럭 처리로 나눴다.
   실제 출력 클럭 핀 지연을 고려해 내부 SD 상승 에지보다 10ns 뒤에 샘플링한다.
   25MHz 전송 속도와 100MHz fabric 클럭은 유지한다. 출력 데이터와 출력 허용은 SD 하강 위상에서만 바뀐다.
   시뮬레이션 assertion과 20ns 지연 카드 모델을 추가했다.
6. 복사한 Linux 기준 트리에 원본을 가리키는 심볼릭 링크가 있었다. 이번 작업의 추가 구문 네 곳을 원본에서
   정확히 제거하고 작업본에는 보존한 뒤, 소스 파일을 독립 복사본으로 바꿨다. 이후 빌드는 외부 절대 링크를 거부한다.
7. 4-master 중재기의 `% MASTERS` 계산은 5-master에서 긴 나머지 연산 회로가 됐다.
   동일한 순환 우선순위를 두 번의 비교·선택으로 구현하고, 다음 순번도 마지막 인덱스 비교로 계산한다.
   시뮬레이션에서는 변경 전 알고리즘과 선택 결과가 매 클럭 같은지 assertion으로 비교한다.
8. 보드용 `kfb_axi_mig.sv`의 RAM 목적지 검사 두 곳에 고정값 7이 남아 있었다.
   주변장치 확장 후 목적지 번호가 바뀌면서 DDR 읽기가 거부되는 문제를 실제 연결 RTL을 포함한 시험에서 찾았다.
   두 곳을 공통 `RAM_PORT` 상수로 바꾸고 native backend 시험 3개가 통과했다. AMD MIG IP 내부 수정은 아니다.

IOB 추가 전 저장소 OOC 내부 타이밍: fabric 100MHz, WNS +2.438ns, WHS +0.058ns,
TNS/THS 0. LUT 1,604, FF 1,267, LUTRAM 128 LUT(전체 LUT에 포함), BRAM/DSP 0.
이 OOC 실행은 외부 포트 지연을 제외한다. 포트 지연 미설정 및 OOC 구성 전압 경고를 포함하며,
전체 보드의 DRC/SD 핀 타이밍 통과 근거로 사용하지 않는다.

최신 SD I/O 전용 배치·배선 시험(io_probe_v3): fabric 100MHz, SD 25MHz,
WNS +2.247ns, WHS +0.121ns, TNS/THS 0, DRC 0건. CMD/DAT 입력 5개가 ILOGIC에 배치됐고,
입력 setup/hold 관계 30ns/-10ns, 출력 관계 20ns/-20ns를 리포트에서 확인했다.
이것은 실제 핀을 쓰는 소형 타이밍 시험 설계이며 CPU/MIG/HDMI를 포함하지 않는다.
시험 설계용 비트스트림을 보드에 올리지 않는다. 전체 보드 구현은 별도로 판정한다.

검증 범위:

* Verilator: native SD 1/4비트 읽기·쓰기, R2/R7/SCR, CRC/timeout 오류, 지연 입력, DMA 768개 무작위 descriptor,
  5-master 중재/원자적 잠금/예약 무효화, PLIC·CSR 인터럽트, 부팅 실패 차단 및 런타임 소유권 전환 PASS.
* 실제 SD 이미지의 firmware/kernel/DTB를 카드 모델에서 RTL 로더로 읽고 mock DDR와 바이트 비교 PASS.
  이 시험은 CPU에서 Linux를 실행하지 않으며 DDR 초기 지우기 길이만 4096바이트로 줄인다.
* 기존 CPU+BOSIO 실행 회귀 PASS. 이 시험에서는 새 저장소 master를 idle로 둔다.
  마지막 MIG 연결 수정 뒤에는 보드용 AXI→MIG bridge/native arbiter와 mock DDR를 사용하는 동일 회귀 6개도 PASS했다.
  근거는 `validation/cpu_bosio_native_regression.log`이다.
* 실제 CPU RTL 펌웨어가 저장소 MMIO를 제어하는 별도 시험: native 카드 초기화 뒤 SD 읽기·쓰기·재읽기,
  4KiB 경계를 넘는 DMA 복사, 패턴 채우기와 결과 데이터 비교, M 외부 인터럽트 4회/S 1회,
  PLIC claim/complete, CDC 및 DMA 쓰기에 따른 384회 예약 무효화를 검사한다.
  최신 실행 결과는 `validation/cpu_storage_seed*.log`에서 확인한다.
  DDR과 카드는 mock이며 Linux 드라이버 실행 시험은 아니다. raw 부트 로더는 별도 이미지 시험으로 검사한다.
* 보드용 AXI→MIG 연결 및 native arbiter까지 포함한 CPU 저장소 시험 3개 seed PASS.
  SD DMA 주소 0xbffff000, fill 마지막 주소 0xbffffffc, M/S 인터럽트 5회/2회와 snoop 576회도 확인했다.
  이 시험의 DDR 저장소는 behavioral model이며 MIG PHY나 실제 메모리 칩을 검증한 것은 아니다.
* Linux 빌드, raw CRC/MBR 비중첩/ext4 fsck 검사 PASS.
* 같은 이미지의 payload를 쓰는 QEMU에서 BusyBox 셸, 계산, 상위 메모리 16페이지 검사 PASS.
  QEMU에는 이번 SD 하드웨어 모델이 없으므로 복구 셸 경로다. MMC 드라이버/ext4 런타임 성공 근거가 아니다.

## 전체 보드 구현 완료 (2026-11-10)

Vivado 2022.2, `xc7a200tfbg484-2`, 실행 디렉터리
`D:/temp/gen3bosio/sd4-dma/board_v6_incremental`의 최종 결과다.
CPU, 두 투영코어와 출력코어, 1GiB용 MIG, HDMI, 주변장치, 새 SD·DMA·PLIC을 포함한다.
기존 성공 체크포인트의 물리 배치를 재사용했지만, 구현 입력은 이번 수정 RTL의 합성 결과다.
합성 입력·체크포인트·검증 이미지의 SHA-256 일치를 확인했다.

| 항목 | 배선 후 결과 |
|---|---:|
| LUT | 114,075 (사용 가능량의 85.26%) |
| FF | 74,189 |
| BRAM 36Kb 환산 | 101.5 |
| DSP48 | 62 |
| 점유 Slice | 32,792 / 33,450 (98.03%) |
| WNS / TNS | +0.034ns / 0ns |
| WHS / THS | +0.027ns / 0ns |
| 배선 오류 | 0 (168,973개 배선 대상 net 연결 완료) |

CPU 50MHz(20ns), fabric 100MHz(10ns), SD 최대 25MHz, pixel 74.25MHz,
serializer 371.25MHz 제약을 유지했다. CPU/fabric setup uncertainty도 0.300ns 그대로다.
CPU 내부 최악 setup slack은 +0.646ns이며 LSQ RAM 출력에서 LSU 주소 변환 레지스터로 가는 경로다.
전체 최악 경로는 `boot/state_reg[2]` → SD 버퍼 주소·데이터 선택 및 CRC 관련 논리 →
`storage/phy/sd_dat_o_reg[0]`이다. 100MHz 경로의 데이터 지연은 8.989ns이고,
그중 배선이 7.445ns다. 배선 직후 -0.185ns였으나 물리 최적화로 +0.034ns가 됐다.
클럭 완화나 기능 제거는 하지 않았다. Slice 점유율이 높고 최악 slack 여유가 작으므로
다음 기능을 추가한 뒤에도 전체 배선을 다시 검증해야 한다. CPU 100MHz 달성을 의미하지 않는다.

계층별 최종 LUT/FF는 CPU 68,535/25,708, BOSIO 30,762/37,809,
MIG 5,761/5,025, AXI fabric 2,818/132, SD·DMA 1,532/1,254,
PLIC 99/112, HDMI 변환부 201/139다. 상위·하위 계층 수치를 중복 합산하지 않는다.

최종 DRC Error/Critical은 0이고 기존 MIG 내부 Warning만 5건 남았다:
BUFC-1 4건(미사용 DQS 입력 버퍼), REQP-1709 1건(MIG PLL 출력 버퍼 종류).
기존 보드 리포트와 같은 항목이며 MIG IP를 수정하거나 경고를 waive하지 않았다.
CDC Warning/Critical은 0, Info는 CDC-3 19건과 CDC-9 18건이다.
Gray pointer 68비트의 최대 지연·동기화 속성과 bus skew 검사도 통과했다.
재사용 배치 도중의 부분 배선 리포트에 있던 PDIL/RTSTAT 항목은 최종 DRC에 남아 있지 않다.

원본 Vivado 로그에는 별도로 Project 1-1108 Critical Warning 1건이 있다.
이는 incremental 실행 속도를 위해 사용자 clock uncertainty를 무시하라고 제안하는 메시지다.
그 제안은 적용하지 않았다. 따라서 원본 로그 전체의 Critical Warning이 0이라고 보고하지 않는다.

SD CMD/DAT 입력 5개는 ILOGIC에 배치됐다. 최악 SD 입력 setup/hold slack은
+7.901ns/+11.973ns, 출력 setup/hold slack은 +11.344ns/+13.091ns다.
입력 30ns/-10ns, 출력 20ns/-20ns의 위상 관계 검사도 통과했다.
이 수치는 설정한 카드/PCB 지연 예산에 대한 결과이며 실측 신호 품질 검증은 아니다.

`check_timing -verbose`의 외부 I/O 범위도 별도로 확인했다. `ddr3_reset_n`과 HDMI clock/data의
양극 출력 4개에는 외부 수신기 output-delay 예산이 지정돼 있지 않다. MIG의 초기화 reset 및
공식 HDMI IP의 전용 출력 경로를 유지한 상태이며, 이번 timing PASS를 실제 DDR/HDMI 수신기의
모든 전기적 조건을 검증한 결과로 확대하지 않는다. UART·SPI MISO·I2C 입력 7개는 비동기 입력이므로
동기화기 첫 단계까지 최대 지연을 제한한 경로이고, 외부 reset은 비동기 assert 경로를 제외한다.
`sd_dclk`는 출력 clock으로 정의됐으며 SD CMD/DAT에는 입력·출력 setup/hold 제약이 있다.
근거는 `board_reports/io_timing_coverage.rpt`다.

추가 읽기 전용 검사에서 기존 `inspect_board_io.tcl`은 다른 구현 전략의
`projection0_input_arithmetic` pblock을 요구해 그 후속 배치 검사에서 중단됐다.
이번 전략은 그 pblock을 사용하지 않는다. I/O 범위 검사는
`software/storage/inspect_io.tcl`로 분리해 실행했으며 최종 DRC·DSP 입력 레지스터 검사도 별도로 통과했다.
이 보조 검사기의 중단을 RTL 실패나 전체 보드 배선 실패로 기록하지 않는다.

최종 파일은 `D:/temp/gen3bosio/sd4-dma/candidate/`에 모았다.

* `ORYUKDO-KFB-SD4-DMA-v1.bit`: 이번 소스의 전체 보드 비트스트림.
* `ORYUKDO-KFB-SD4-DMA-v1.img`: 263MiB SD 이미지, raw 부팅 파티션과 256MiB ext4 `/data`.
* `board_manifest.json`, `package_sha256.json`: 결과와 파일 식별 해시.
* `board_reports/`: 합성·배선·핀·CDC·DRC·타이밍 원본 근거.
* `ORYUKDO-SD4-DMA-rtl-software-tests.tar.gz`: RTL·소프트웨어·검증·한국어 문서.
* `linux-6.12-sd4-dma-source.tar.gz`: 이번 커널 빌드에 사용한 독립 Linux 소스.

이 PC에서 전체 보드 구현을 다시 실행하는 명령(작업본 루트에서 실행, 새 출력 디렉터리 사용):

```powershell
python soc/board/run_board.py D:/temp/gen3bosio/sd4-dma/rebuild --ip D:/temp/gen3bosio/sd4-dma/ip/kfb_bosio_mig.srcs/sources_1/ip/mig_7series_0/mig_7series_0.xci --strategy area-medium-incremental --reference D:/temp/gen3bosio/coldboot/bridge_timing_refine_v1/route/routed.dcp
```

이번 채택 실행은 `software/storage/reuse_synth_route.py`로 `board_v6/synth/optimized.dcp`를
재사용했다. 합성부터 다시 수행하는 위 명령과 같은 RTL·제약·물리 구현 절차다.
MIG 생성물과 이전 배선 reference 경로는 로컬 의존성이며 소스 압축본에 대형 DCP는 넣지 않았다.
다른 PC에서 정확히 같은 재사용 실행을 하려면 이 두 입력도 옮기고 해시를 대조해야 한다.

최종 비트스트림 SHA-256:
`fe1ce8e52f30f1b9bd7bad944a0bf6f981eef9bba01438c0d26b40da6126fdf0`

SD 이미지 SHA-256:
`feee0045461772ce1c6ed8ea342a7c3d81b39383b7cbcb0f1f9b25b749a8006e`

## 현재 제한과 남은 검증

* 첫 구현은 명령당 최대 512바이트, 데이터 블록 1개이다. Linux는 요청을 나눠 처리한다.
  CMD18/CMD25 연속 다중 블록 전송은 아직 지원하지 않는다. 이론 전송률 12.5MB/s를 실측 속도로 보고하지 않는다.
* Linux MMC 드라이버는 512바이트 coherent bounce buffer를 쓴다. CPU의 바이트 단위 I/O는 제거했지만,
  Linux scatterlist와 bounce buffer 사이의 메모리 복사까지 제거한 것은 아니다.
* DMA는 4바이트 정렬 비중첩 복사 및 fill만 지원한다. 임의 길이/비정렬/중첩 memmove가 아니다.
* 수락된 AXI 전송을 타임아웃으로 취소하지 않는다. SD 드라이버의 소프트웨어 타임아웃 시 호스트를 격리하고
  DMA 버퍼를 재사용/반환하지 않는다. 복사 DMA의 실행 중 terminate는 -EBUSY를 반환한다.
* 카드 전원 스위치와 연결된 card-detect 입력이 회로도에서 확인되지 않았다. 실행 중 카드 교체를 지원하지 않는다.
* SD I/O XDC의 카드 출력 지연/PCB 여유는 설계 예산이다. 실제 카드와 보드에서 확인할 필요가 있다.
* 새 Linux 드라이버의 실보드 탐색, ext4 마운트/영구 쓰기, 재부팅 보존, 실제 대역폭은 아직 검증하지 않았다.
* 새 전체 CPU RTL에서 Linux 셸까지 이어지는 콜드 부팅도 별도 통합 검증 항목이다.
* 저장소 블록 OOC 배선 결과는 전체 SoC/MIG/HDMI/SD I/O 타이밍 통과를 의미하지 않는다.

전체 보드 구현 상태와 리소스는 `validation/status.json`, `validation/board_implementation.json`에 기록했다.
이번 비트스트림과 SD 이미지를 한 쌍으로 사용한다. 실보드 검증 절차는 `BOARD_STORAGE_CHECK_KO.md`를 따른다.

# ORYUKDO-3d5i_BOSIO_SoC

## 최신 추가: SD 4비트·DMA·ext4 (2026-11-10)

[SD4·DMA 구성](variants/sd4-dma/README.md)에 native 4비트 SD, CPU 제어 DMA, PLIC 외부 인터럽트,
Linux MMC/DMAengine 드라이버와 영구 ext4 `/data`를 추가했다. BusyBox와 BoAYO native-v2는 보존했다.
소스·테스트·원본 검증 로그·Vivado 리포트는 `variants/sd4-dma/`에 함께 있다.

**새 구성은 시뮬레이션과 전체 보드 합성·배선을 통과했으며, 실보드 SD 파일시스템 검증은 아직 하지 않았다.**
기존 검증본과 혼동하지 않도록 루트의 2026-11-08 소스와 증거를 보존했다. 두 구성의 소스를 섞지 않는다.

| 항목 | SD4·DMA 전체 보드 배선 결과 |
|---|---:|
| CPU / fabric / SD 최대 | 50 / 100 / 25 MHz |
| LUT / FF / BRAM / DSP | 114,075 / 74,189 / 101.5 / 62 |
| Setup WNS / Hold WHS | +0.034 ns / +0.027 ns |
| TNS / THS | 0 / 0 |
| CDC Warning·Critical | 0 |
| DRC | Error·Critical 0, 기존 MIG Warning 5건 |

[새 사전 릴리스: 비트스트림·SD 이미지·Linux 전체 소스](https://github.com/VARZero/ORYUKDO-3d5i_BOSIO_SoC/releases/tag/sd4-dma-20261110-candidate)
에서 파일을 받는다. 새 비트스트림과 새 SD 이미지는 한 쌍으로 사용해야 한다.

- [추가 기능과 검증 범위](variants/sd4-dma/README.md)
- [상세 구조·수정 내역·타이밍 분석](variants/sd4-dma/README_STORAGE_KO.md)
- [실보드 확인 절차](variants/sd4-dma/BOARD_STORAGE_CHECK_KO.md)
- [결과·소스·산출물 해시](variants/sd4-dma/provenance/board_manifest.json)

게시본 무결성 확인: `python scripts/verify_sd4_publication.py`.
대용량 이미지는 Git 이력에 넣지 않고 사전 릴리스 첨부파일로 관리한다.

## 기존 실보드 부팅 검증본 (2026-11-08, 루트 디렉터리)

PZ-A7200T-KFB에서 Linux 6.12와 BusyBox UART 쉘의 부팅을 확인한 ORYUKDO Gen3 + BOSIO SoC 소스이다. 기준은 **2026-11-08 실보드에서 검증한 TLB8 비트스트림과 trace-v2 진단 SD**의 조합이다.

비트스트림, SD 이미지, 전체 Linux 소스 압축본은 [실보드 검증본 Release](https://github.com/VARZero/ORYUKDO-3d5i_BOSIO_SoC/releases/tag/board-20261108-tlb8-trace-v2)에서 받는다. 첨부한 `SOC-SHA256SUMS.txt`로 다운로드한 파일의 해시를 확인할 수 있다.

ORYUKDO 스케줄러는 3 Decode / 5 Issue이며 실행기는 Branch·CSR 1개, ALU 2개, MULDIV 1개, LSQ 1개로 구성한다. CPU에는 Sv32 MMU와 명령·데이터 측 각각 8엔트리 TLB가 있다. MIG를 통한 DDR3L 1GiB, SD 부트 로더, UART 콘솔, BOSIO 투영코어 2개·출력코어·센서 허브, HDMI 출력 연결, 추가 AXI UART·SPI·I2C를 포함한다.

## 문서

- [SoC 구조와 주소 맵](docs/구조.md)
- [소스 구성과 Linux 변경 내역](docs/소스_구성.md)
- [빌드 및 검증 방법](docs/빌드.md)
- [보드 사용 방법](docs/보드_사용.md)
- [검증 결과와 한계](docs/검증.md)
- [라이선스와 외부 소스](THIRD_PARTY.md)

## 확인한 결과

| 항목 | 결과 |
|---|---|
| 실보드 부팅 | JTAG 구성 → SD 적재 → OpenSBI → Linux → BusyBox 쉘 |
| UART 명령 | 산술 연산, 커널 버전, 메모리 용량 확인 PASS |
| 상위 DDR | 0xbee00000..0xbef08ffc의 16페이지 읽기·쓰기 PASS |
| CPU / fabric | 50 / 100 MHz |
| LUT / FF / BRAM / DSP | 108,798 / 72,969 / 101.5 / 62 |
| 배선 후 Setup WNS / Hold WHS | +0.101 ns / +0.023 ns |
| TNS / THS | 0 / 0 |
| CDC Warning·Critical | 0 |
| DRC | Error·Critical 0, 생성된 MIG 내부 Warning 5개 |

이 수치는 MIG·HDMI를 포함한 보드 전체 구현의 결과다. HDMI의 실제 화면, BoAYO WM, Linux용 BOSIO 드라이버는 검증 완료 항목이 아니다. 전체 RTL의 SD→쉘 부팅 역시 아직 PASS로 인정하지 않는다. 진단 표시 없는 일반 커널의 실보드 재시험도 별도이다.

## 디렉터리

| 경로 | 내용 |
|---|---|
| `rtl/`, `gen2/` | 사용 중인 오륙도 스케줄러와 을숙도 기반 의존 모듈 |
| `soc/rtl/` | CPU, EX, CSR, MMU/TLB, SoC 및 보드 적용 스케줄러 |
| `soc/bosio/`, `soc/vendor/` | AXI 연결, BOSIO 투영·출력·센서 RTL |
| `soc/board/` | 보드 최상위, SD, DDR 연결, HDMI 연결, 핀 제약, Vivado 스크립트 |
| `software/linux/` | Linux 6.12 패치, 수정 파일 전체, 실제 설정, 원본 해시 |
| `software/userspace/` | BusyBox·musl 빌드, init와 상위 메모리 검사 소스 |
| `software/firmware/` | 검증한 OpenSBI·Linux·DTB 및 initramfs 실행 파일 |
| `scripts/` | 소스 복원, Linux 빌드, 입력 일치 검사 |
| `evidence/` | 실제 UART 기록과 배선 후 보고서 |
| `provenance/` | 보드 입력 및 산출물 해시 |
| `artifacts/` | 로컬 비트스트림·SD·전체 Linux 소스 압축본. Git 추적 제외 |

처음에는 `python scripts/verify_sources.py`로 소스 일치를 확인한다. Linux 전체 소스는 `scripts/prepare_linux.py`로 정확한 원본과 패치에서 복원하거나, 함께 준비한 전체 소스 압축본을 사용한다. RTL과 공식 HDMI IP 본문은 게시 준비 과정에서 수정하지 않았다.

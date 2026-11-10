# SD 4비트·DMA·영구 파일시스템 구성

2026-11-10에 로컬 검증과 PZ-A7200T-KFB 전체 보드 구현을 완료한 독립 작업본이다.
이 디렉터리를 프로젝트 루트로 사용한다. 상위 저장소 루트의 구형 RTL을 섞지 않는다.
게시 과정에서는 검증한 RTL·드라이버·실행 스크립트 234개를 변경하지 않았으며 해시로 대조했다.

## 추가한 기능

1. native SD: 전원 인가부터 1비트 초기화 후 4비트 전송, 초기화 400kHz·최대 25MHz.
   512바이트 버퍼, CRC7/CRC16, 응답·오류·타임아웃 처리를 포함한다.
2. DMA: Linux 런타임 SD 버퍼↔DDR, CPU 명령에 의한 DDR 복사·채우기.
   최대 64바이트 burst, 4KiB 경계 분할, 잘못된 주소·AXI 오류 처리를 포함한다.
3. 중재·인터럽트: 기존 CPU/BOSIO 버스에 저장소 master를 추가하고 PLIC의 M/S context를 연결했다.
   DMA 쓰기는 CPU 원자적 접근 잠금과 예약 무효화 경로도 통과한다.
4. Linux 저장소: MMC/DMAengine 드라이버와 ext4 `/data`.
   기존 BusyBox와 BoAYO native-v2 실행 파일은 보존했다.

CPU의 3 Decode / 5 Issue, 기존 스케줄러 알고리즘, MIG·공식 HDMI IP 본문은 유지했다.
AXI 중재기의 5-master 순환 선택을 최적화했고, 보드 AXI→MIG 연결에 남아 있던 RAM 목적지 고정값을
공통 `RAM_PORT`로 수정했다. 자세한 수정 목록은 [상세 문서](README_STORAGE_KO.md)에 있다.

## 검증 결과

| 범위 | 결과와 한계 |
|---|---|
| native SD | 응답, 1/4비트 전송, 지연 입력, CRC/timeout/오류 처리 PASS |
| DMA·중재 | 768개 무작위 descriptor, 5-master 경쟁, 오류 후 복구 PASS |
| 실제 CPU RTL | SD 읽기·쓰기·재읽기, DMA, M/S 인터럽트, 상위 DDR 주소 검사 PASS |
| 보드 연결 RTL | AXI→MIG bridge/native arbiter + mock DDR의 CPU·BOSIO 회귀 PASS |
| 실제 이미지 RTL 로더 | 카드 모델→부트 로더→mock DDR payload 비교 PASS; CPU의 Linux 실행 시험은 아님 |
| Linux·파일시스템 생성 | 커널 빌드, raw CRC/MBR, ext4 fsck PASS |
| QEMU | 같은 payload의 BusyBox 복구 셸·산술·상위 메모리 검사 PASS; 새 SD 장치 모델 없음 |
| 전체 보드 구현 | MIG·HDMI 포함 합성·배선·비트스트림 생성 PASS |
| 실보드 MMC/ext4 | 아직 수행하지 않음 |

CPU 50MHz, fabric 100MHz에서 WNS +0.034ns, WHS +0.027ns, TNS/THS 0이다.
LUT 114,075, FF 74,189, BRAM 101.5, DSP 62이며 Slice 점유율은 98.03%다.
CDC Warning/Critical은 0, 최종 DRC는 기존 MIG 내부 Warning 5건이다.
원본 도구 로그의 Project 1-1108 Critical Warning 1건은 incremental 실행 속도를 위한
clock uncertainty 무시 제안이다. 그 제안을 적용하지 않고 0.300ns 제약을 유지했다.
외부 HDMI 수신기·DDR reset 등의 I/O 검증 범위와 작은 타이밍 여유는 상세 문서에 명시했다.

## 소스와 근거

| 경로 | 역할 |
|---|---|
| `rtl/`, `gen2/`, `soc/` | 이번 비트스트림의 RTL·보드 제약·검증 소스 |
| `software/storage/` | 새 Linux 드라이버, SD 이미지 생성, 시험·분석 스크립트 |
| `software/storage/linux.config` | 실제 SD4 커널의 설정 |
| `software/bosio/gen3-bosio.dts` | SD·DMA·PLIC을 추가한 장치 트리 |
| `validation/` | Verilator/QEMU·이미지·빌드 원본 로그 |
| `evidence/board/` | 합성·배선·DRC·CDC·I/O 타이밍 리포트 |
| `provenance/` | 검증 소스, 입력, 이미지, 비트스트림 및 공개 첨부파일 해시 |

`software/linux/`의 세 진단 패치와 관련 manifest는 상속된 trace-v2 기준 자료다.
**이번 커널 전체의 정확한 소스는 사전 릴리스의 `linux-6.12-sd4-dma-source.tar.gz`이다.**
구형 `scripts/prepare_linux.py`만으로 이번 커널 소스를 복원했다고 간주하면 안 된다.
새 드라이버 원문은 Git에도 포함했다. 전체 Linux 압축본과 드라이버 해시 일치를 확인했다.

## 실행과 재현 범위

WSL/Linux에서 이 디렉터리를 기준으로 실행한다. Verilator, RISC-V bare-metal GCC,
Vivado의 XPM 참조 등 기존 도구가 필요하다.

```sh
bash software/storage/test.sh
bash software/storage/test_cpu.sh
KFB_NATIVE_BACKEND=1 bash software/storage/test_cpu.sh
```

빌드·이미지 생성·패키지 스크립트에는 당시 PC의 `/var/tmp/oryukdo-*`, 원본 userspace,
BoAYO `root_list.py`, Vivado 설치 경로 등의 로컬 의존성이 남아 있다.
다른 PC에서 아무 준비 없이 재빌드된다고 보장하지 않는다. 입력 경로를 준비하거나 바꿔야 하며,
재빌드 결과는 별도로 검증한다. 현재 보존한 실행은 소스 해시가 같은 기존 합성 checkpoint와
이전 보드 배선 checkpoint를 재사용했다. 대형 DCP와 Vivado 생성 IP는 Git에 넣지 않았다.

## 다운로드와 남은 작업

[사전 릴리스](https://github.com/VARZero/ORYUKDO-3d5i_BOSIO_SoC/releases/tag/sd4-dma-20261110-candidate)의
비트스트림과 SD 이미지를 한 쌍으로 사용한다. `SD4-SHA256SUMS.txt`로 파일을 확인한다.
SD 이미지는 263MiB이며 두 번째 파티션이 256MiB ext4이다. 카드 전체 용량으로 자동 확장하지 않는다.
GitHub 소스 ZIP과 검증 당시 RTL 압축본은 포장 범위가 다르므로 서로 같은 파일로 간주하지 않는다.

보드 접속·카드 기록·FPGA 업로드는 이번 작업에서 하지 않았다.
[실보드 절차](BOARD_STORAGE_CHECK_KO.md)에 따라 카드 탐색, `/data` 마운트·쓰기·재부팅 후 보존을 확인해야 한다.
전체 CPU RTL에서 이번 Linux가 셸까지 부팅되는 시험, 실제 카드 속도 측정도 미완료다.
raw 부트 로더는 기존 바이트 입력 경로를 유지한다. 연속 다중 블록 SD 명령과
BoAYO 렌더링의 DMA 가속은 이번 버전의 기능이 아니다.

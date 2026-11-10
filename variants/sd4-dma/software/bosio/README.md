# ORYUKDO Linux BOSIO 드라이버 · 코어 구동 SW

> 현재 소스는 ABI 3이다. [UART WASD 시야·중앙 클릭](../boayo/UART_KEYS.md)의 프레임 경계 카메라 변경을 추가했다. SCRATCH 버퍼와 BoAYO 연결은 [V2 설명](../boayo/DUAL_PROJECTION.md)을 따른다. 기존 `reports/`와 `reports_dual/`은 각각 ABI 1·2 기록이며, 새 결과는 `../boayo/reports_uart/`에 보관한다.

2026-11-08 실보드 부팅 기준 소스를 별도 로컬 브랜치 `bosio-linux-driver`에서 확장했다. **이번 작업은 보드를 연결하지 않고 수행했다.** 기존 보드 RTL·MIG·HDMI IP는 변경하지 않았다.

## 구현한 경로

```text
bosioctl / 향후 BoAYO backend
           ↓ ioctl
Linux 내장 드라이버 /dev/bosio0
           ↓ 공통 C 제어 엔진
투영코어 0 ─┐
            ├─ AXI 중재 ─ DDR 비활성 장면 ─ 출력코어 ─ RGB888 영상 스트림
투영코어 1 ─┘
```

기존 테스트는 투영 결과 두 개와 별도의 출력 테스트 장면을 검사했다. 새 테스트는 **투영한 타일 자체를 출력 장면의 payload에 배치하고 출력코어가 그 주소를 읽도록 연결**한다. 초기 장면은 왼쪽 빨강/오른쪽 초록, 다음 장면은 왼쪽 파랑/오른쪽 노랑이다. 투영기는 원본 RGB 텍스처를 읽어 RGB332 인덱스를 생성하며, 단순 clear 색으로 검사를 대신하지 않는다.

## 파일

| 경로 | 역할 |
|---|---|
| `driver/bosio_kfb.c` | Linux 6.12 플랫폼·misc 드라이버, 예약 DMA, 복사·권한·단일 사용자·수명 관리 |
| `include/bosio_uapi.h` | RV32/호스트 공통 고정 폭 ioctl ABI |
| `common/bosio_engine.c` | 레지스터 설정, 두 코어 완료 추적, 장면 게시·정지·시간 초과 격리 |
| `tools/bosioctl.c` | 상태 확인과 두 투영코어→출력 데모 |
| `gen3-bosio.dts` | 장치 주소와 16MiB 전용 DMA 예약 영역 |
| `tests/test_rtl.cpp`, `tb_bosio_driver.sv` | 실제 RTL과 공통 C 엔진의 연결 테스트 |
| `tests/test_engine.c` | 완료 순서·범위·오버플로·소유권·시간 초과 검사 |
| `reports/` | 실행 로그, 커널 심볼 및 검증 요약 |

## Linux 드라이버 계약

- 장치: `/dev/bosio0`, 권한 0600, `CAP_SYS_RAWIO` 필요, 한 프로세스만 열 수 있다. 같은 파일의 여러 스레드 요청도 mutex로 직렬화한다.
- 투영 제어 주소: `0x20000000`, `0x20010000`; 출력 제어 주소: `0x20020000`.
- DT의 `shared-dma-pool` `0xbd000000..0xbdffffff` 16MiB를 전용 사용한다. 원래 표시 버퍼 `0xbf800000..0xbfffffff`와 겹치지 않는다. Linux의 가용 RAM은 이 예약만큼 줄어든다.
- `dma_alloc_coherent`를 사용하고 CPU→장치 게시와 완료 이후 접근에 DMA barrier를 적용한다. 물리 주소를 사용자 요청에서 직접 받지 않으며 임의 MMIO·mmap도 제공하지 않는다.
- 사용자 데이터는 임시 복사본을 완전히 받은 뒤 DMA 버퍼에 기록한다. copy fault 중간의 부분 데이터가 실행되는 것을 막는다.
- Descriptor는 18워드, 타일 결과는 256워드이다. 텍스처 범위·타일 결과 범위·두 코어의 쓰기 중첩을 시작 전에 검사한다. 최대 코어당 64개 작업이다.
- 두 코어를 먼저 시작한 뒤 각 코어의 clear-on-read `ap_done`을 따로 기억한다. GIE/IER는 끄며, 아직 연결하지 않은 Linux 외부 인터럽트에 의존하지 않는다.
- 출력 중인 장면은 업로드와 투영 쓰기를 거부한다. 새 장면의 **active base가 전환되고 pending/busy가 해소된 것**을 확인한 뒤 이전 버퍼를 반환한다. 요청 승인이나 metadata 적재만으로 반환하지 않는다.
- 시간 초과·불확실한 MMIO 실패 뒤에는 장치를 poisoned 상태로 고정한다. 종료·close로 DMA 메모리를 반환하지 않는다. 자동 복구는 제공하지 않으며 보드 전체 재설정 후 다시 시작해야 한다.
- 드라이버는 커널 내장 전용이며 모듈 빌드와 sysfs unbind를 허용하지 않는다. 플랫폼 수명 동안 DMA 메모리를 유지한다.

일반적인 데이터 갱신은 비활성 장면에 필요한 범위만 업로드하고 해당 타일만 투영할 수 있다. 빈 작업은 코어를 시작하지 않는다. 이 단계는 BoAYO의 dirty-tile 탐색·가림 처리·앱별 캐시 구현을 포함하지 않는다.

## ioctl

| 명령 | 의미 |
|---|---|
| `BO_GET_INFO` | ABI, BS25/DTF1 식별값, 출력 상태, active bank, poisoned 여부 |
| `BO_UPLOAD` | texture/descriptor0/descriptor1/scene0/scene1 중 지정 영역의 일부 업로드 |
| `BO_RUN` | 두 투영기의 작업 시작 및 모두 완료 대기; status·written_cells 반환 |
| `BO_PRESENT` | palette/directory 검증, 카메라 설정, 비활성 장면의 프레임 경계 전환 완료 대기 |
| `BO_STOP` | 출력 비활성화 후 파이프라인·DDR 요청 배출 확인 |

현재 ABI1은 실행 중 카메라·해상도를 동시에 바꾸는 요청을 거부한다. 변경하려면 먼저 STOP으로 배출한 뒤 PRESENT한다. 같은 카메라의 일반 장면 교체는 출력이 계속 실행되는 상태에서 프레임 경계로 전환한다. 데모는 M=32와 AA 비활성 상태로 정확한 픽셀 비교를 한다. AA·센서 모드의 일반 사용자 API, Linux IRQ, 강제 DMA 취소는 다음 단계이다.

## 실행한 검증

| 검사 | 결과 |
|---|---|
| 실제 투영코어 2개 + 실제 출력코어 + 실제 AXI fabric, DDR 모델 | seed 1/7/23 모두 PASS |
| 각 seed의 픽셀 비교 | 1,847,040픽셀, SOF/EOL와 backpressure 유지 검사 |
| 각 seed의 투영 쓰기 | 코어당 512워드, 두 장면 각각 256워드 |
| 각 seed의 출력 DDR 읽기 | 10,016 beat |
| 각 투영 작업의 written_cells | 1,024, 실제 payload 256워드 전체 검사 |
| 메타데이터·타일 뒤 guard | 덮어쓰기 없음 |
| 프레임 교체 | 구/신 장면의 색이 한 프레임에 섞이지 않음 |
| 불법 중첩·active 버퍼 쓰기·빈 작업·시간 초과 후 격리 | PASS |
| 공통 엔진 단위 검사 | 19개, ASan/UBSan PASS; 양쪽 완료 순서 포함 |
| RV32 Linux Image | 드라이버를 내장하여 컴파일·링크 PASS, 실제 심볼 확인 |
| bosioctl | RV32 ILP32 정적 ELF 빌드 PASS |
| 후보 SD 페이로드·CRC | PASS |
| 기존 보드 RTL·제약 입력 | 125개 원문 일치, 공식 IP 15개 무결성 PASS |

**검증 경계:** RTL 검사에서는 호스트 프로그램이 Linux 드라이버와 같은 C 제어 엔진을 호출한다. CPU/Linux의 ioctl 실행, 커널 DMA API의 실제 보드 동작을 RTL에서 부팅하여 검사한 것은 아니다. 메모리는 지연·backpressure를 넣은 모델이며 MIG PHY·DDR calibration·HDMI 직렬화·CPU CDC는 이 새 테스트의 범위 밖이다. 실보드에서 새 드라이버를 실행하거나 HDMI 화면을 확인하지 않았다. BoAYO WM도 아직 이식하지 않았다.

## 재현

프로젝트 루트에서 Linux/WSL로 실행한다.

```sh
bash software/bosio/tests/run_engine.sh
bash software/bosio/tests/run_rtl.sh
```

Verilator와 C/C++ 컴파일러가 필요하다. 기존 장시간 콜드 부팅을 재시작하지 않고 이 테스트만 새 작업 경로에서 실행한다.

RV32 도구와 커널을 만들 때:

```sh
# 기존 userspace 빌드로 RV32 musl wrapper를 준비하거나 기존 wrapper를 지정한다.
# bash software/userspace/build_busybox.sh /var/tmp/bosio-toolchain
RV32_CC=/var/tmp/bosio-toolchain/tool/rv32-gcc \
  bash software/bosio/scripts/build_userspace.sh /var/tmp/bosio-user

# trace-v2 Linux 소스는 프로젝트의 scripts/prepare_linux.py로 복원한다.
bash software/bosio/scripts/build_kernel.sh \
  /path/to/linux-6.12 /var/tmp/bosio-kernel /var/tmp/bosio-user/bosioctl
```

원본 Linux 소스는 출력 디렉터리에 복사한 뒤 수정한다. 새 Image에는 `bosioctl`이 포함되고, 새 DTB에는 전용 메모리가 예약된다. 후보 SD는 출력 `sd/`에 생성된다. 기존 부팅 이미지나 비트스트림을 덮어쓰지 않는다.

보드를 다시 연결하고 별도 실보드 검증을 시작할 때 사용할 명령은 `bosioctl info`, `bosioctl demo`이다. 데모는 Enter를 누르거나 프로세스가 종료될 때 출력을 정지한다. **현재 후보 이미지는 실보드 검증 전이며, 이 문서는 지금 보드에 기록하라는 지시가 아니다.**

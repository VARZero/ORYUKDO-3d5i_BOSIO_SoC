# ORYUKDO Linux BOSIO 드라이버 · 코어 구동 SW

현재 소스는 **ABI 3**이며 기준은 [UAPI 헤더](include/bosio_uapi.h)와 [공통 제어 엔진](common/bosio_engine.c)이다.
프레임 경계 카메라 변경과 SCRATCH 결과 읽기를 포함한다. 상속된 문서가 가리키던 `software/boayo/` 문서와
과거 `reports*` 폴더는 이 게시본에 포함되지 않아 링크를 제거했다. 현재 저장소 구성은 [후보 안내](../../README.md)를 따른다.

이 드라이버는 2026-11-08 부팅 기준본에서 확장한 BOSIO 제어 소스다. SD4 후보는 이 ABI 3 코드와
이미지의 BoAYO native-v2를 보존했다. SD·DMA·PLIC·보드 bridge 변경은 후보 전체에 별도로 있으며,
MIG·공식 HDMI IP 본문은 유지했다. 새 SD4 이미지의 실보드 BOSIO·HDMI·WASD 동작을 확인했다는 뜻은 아니다.

## 구현한 경로

```text
bosioctl / BoAYO의 BOSIO backend
           ↓ ioctl
Linux 내장 드라이버 /dev/bosio0
           ↓ 공통 C 제어 엔진
투영코어 0 ─┐
            ├─ AXI 중재 ─ DDR 비활성 장면 ─ 출력코어 ─ RGB888 영상 스트림
투영코어 1 ─┘
```

드라이버 단독 RTL 시험 소스는 **투영한 타일 자체를 출력 장면의 payload에 배치하고 출력코어가 그 주소를 읽도록 연결**한다. 초기 장면은 왼쪽 빨강/오른쪽 초록, 다음 장면은 왼쪽 파랑/오른쪽 노랑이다. 투영기는 원본 RGB 텍스처를 읽어 RGB332 인덱스를 생성한다. 아래 검증 절에서 이 시험 소스와 현재 보존된 실행 근거를 구분한다.

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
| `../../validation/` | 이번 SD4 후보의 CPU·BOSIO·저장소 회귀 근거 |

## Linux 드라이버 계약

- 장치: `/dev/bosio0`, 권한 0600, `CAP_SYS_RAWIO` 필요, 한 프로세스만 열 수 있다. 같은 파일의 여러 스레드 요청도 mutex로 직렬화한다.
- 투영 제어 주소: `0x20000000`, `0x20010000`; 출력 제어 주소: `0x20020000`.
- DT의 `shared-dma-pool` `0xbd000000..0xbdffffff` 16MiB를 전용 사용한다. 원래 표시 버퍼 `0xbf800000..0xbfffffff`와 겹치지 않는다. Linux의 가용 RAM은 이 예약만큼 줄어든다.
- `dma_alloc_coherent`를 사용하고 CPU→장치 게시와 완료 이후 접근에 DMA barrier를 적용한다. 물리 주소를 사용자 요청에서 직접 받지 않으며 임의 MMIO·mmap도 제공하지 않는다.
- 사용자 데이터는 임시 복사본을 완전히 받은 뒤 DMA 버퍼에 기록한다. copy fault 중간의 부분 데이터가 실행되는 것을 막는다.
- Descriptor는 18워드, 타일 결과는 256워드이다. 텍스처 범위·타일 결과 범위·두 코어의 쓰기 중첩을 시작 전에 검사한다. 최대 코어당 64개 작업이다.
- 두 코어를 먼저 시작한 뒤 각 코어의 clear-on-read `ap_done`을 따로 기억한다. BOSIO의 GIE/IER는 끄고 완료를 polling한다. 새 PLIC은 SD·복사 DMA용이며 BOSIO 완료 IRQ를 추가한 것은 아니다.
- 출력 중인 장면은 업로드와 투영 쓰기를 거부한다. 새 장면의 **active base가 전환되고 pending/busy가 해소된 것**을 확인한 뒤 이전 버퍼를 반환한다. 요청 승인이나 metadata 적재만으로 반환하지 않는다.
- 시간 초과·불확실한 MMIO 실패 뒤에는 장치를 poisoned 상태로 고정한다. 종료·close로 DMA 메모리를 반환하지 않는다. 자동 복구는 제공하지 않으며 보드 전체 재설정 후 다시 시작해야 한다.
- 드라이버는 커널 내장 전용이며 모듈 빌드와 sysfs unbind를 허용하지 않는다. 플랫폼 수명 동안 DMA 메모리를 유지한다.

일반적인 데이터 갱신은 비활성 장면에 필요한 범위만 업로드하고 해당 타일만 투영할 수 있다. 빈 작업은 코어를 시작하지 않는다. 이 단계는 BoAYO의 dirty-tile 탐색·가림 처리·앱별 캐시 구현을 포함하지 않는다.

## ioctl

| 명령 | 의미 |
|---|---|
| `BO_GET_INFO` | ABI, BS25/DTF1 식별값, 출력 상태, active bank, poisoned 여부 |
| `BO_UPLOAD` | texture/descriptor0/descriptor1/scene0/scene1/scratch 중 지정 영역의 일부 업로드 |
| `BO_RUN` | 두 투영기의 작업 시작 및 모두 완료 대기; status·written_cells 반환 |
| `BO_PRESENT` | palette/directory 검증, 카메라 설정, 비활성 장면의 프레임 경계 전환 완료 대기 |
| `BO_STOP` | 출력 비활성화 후 파이프라인·DDR 요청 배출 확인 |
| `BO_DOWNLOAD` | 완료한 SCRATCH 결과만 사용자 버퍼로 복사 |
| `BO_SET_POSE` | 출력이 구성된 상태에서 180워드 카메라를 게시하고 프레임 경계 pending 해제 대기 |

ABI 3의 카메라 변경은 `BO_SET_POSE`를 사용한다. 단순 AXI 쓰기 승인을 완료로 보지 않고 frame 경계의 pending 해제를 기다린다.
`BO_PRESENT`에서 실행 중 카메라 또는 해상도를 바꾸는 요청은 여전히 거부한다. 해상도 변경은 STOP으로 배출한 뒤 PRESENT한다.
같은 카메라의 장면 교체는 출력이 실행되는 상태에서 frame 경계로 전환한다.
SCRATCH는 두 표시 bank와 분리된 256KiB 공간이며 표시 대상으로 사용하지 않는다.
새 저장소 DMAengine 드라이버가 이 업로드·결과 복사 경로를 자동 가속하지는 않는다.

## 검증 근거와 경계

과거 ABI 1·2 드라이버 단독 시험의 픽셀 수·beat 수와 로컬 보고서 경로를 현재 SD4 결과로 사용하지 않는다.
이 게시본에 포함된 현재 근거는 [CPU/BOSIO 회귀](../../validation/cpu_bosio_regression.log),
[보드 bridge/native backend 회귀](../../validation/cpu_bosio_native_regression.log) 및
[검증 범위](../../../../docs/검증.md)다. 소스의 시험 도구와 보존한 실행 근거는 구분한다.

호스트 C 엔진과 RTL을 연결하는 단독 시험은 CPU/Linux ioctl 실행 시험이 아니며 실제 MIG PHY·DDR calibration·HDMI 수신기를 검증하지 않는다.
현재 SD4 이미지에는 BoAYO native-v2가 보존돼 있으므로 “BoAYO가 아직 이식되지 않았다”는 과거 표현은 적용하지 않는다.
다만 이번 SD4 후보의 실보드 BoAYO·HDMI·WASD 통합 검증은 남아 있다.

## 재현

프로젝트 루트에서 Linux/WSL로 실행한다.

```sh
bash software/bosio/tests/run_engine.sh
bash software/bosio/tests/run_rtl.sh
```

Verilator와 C/C++ 컴파일러가 필요하다. 기존 장시간 콜드 부팅을 재시작하지 않고 이 테스트만 새 작업 경로에서 실행한다.

## 도구 빌드와 현재 SD4 커널의 구분

`tools/bosioctl.c`는 `info|demo`용 도구다. `scripts/build_userspace.sh`에는 RV32 musl wrapper 경로가 필요하다.
`software/userspace/`는 이 후보 디렉터리에 없으므로 상위 기준본의 빌드 도구나 준비한 toolchain을 명시적으로 사용한다.

`software/bosio/scripts/build_kernel.sh`는 상속된 trace-v2 설정·초기 initramfs를 쓰는 과거 BOSIO 단독 경로다.
이 스크립트로 현재 SD4 이미지가 재현된다고 안내하지 않는다. 현재 커널은 릴리스의 전체 Linux 소스와
`software/storage/linux.config`, 저장소 빌드 경로를 기준으로 한다. 로컬 의존성과 명령은 [빌드 문서](../../../../docs/빌드.md)를 따른다.

실보드에서는 `bosioctl info`, 필요시 `bosioctl demo`로 확인할 수 있다. 데모는 Enter 또는 프로세스 종료 시 출력을 정지한다.
장치 제어와 동시에 다른 BoAYO/BOSIO 프로세스를 열 수 없으므로 현재 소유자를 먼저 정리한다.
이 설명은 향후 검증 절차이며 이번 문서 수정에서 보드 실행을 수행했다는 뜻이 아니다.

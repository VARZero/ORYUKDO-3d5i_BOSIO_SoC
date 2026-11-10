# SD 4비트·DMA·ext4 사전 릴리스 — 2026-11-10

PZ-A7200T-KFB용 native SD 4비트, CPU 제어 DMA, PLIC 외부 인터럽트와 Linux MMC/DMAengine·ext4 `/data`를 추가했다.
기존 BusyBox와 BoAYO native-v2를 보존했다. 기존 실보드 검증 소스는 저장소 루트에 유지하고,
이번 소스·검증·문서는 `variants/sd4-dma/`에 별도로 넣었다.

**로컬 기능 검증 및 전체 보드 합성·배선 완료, 실보드 MMC/ext4 검증 전인 사전 릴리스다.**
보드 접속, SD 기록, FPGA 업로드는 수행하지 않았다. 기존 실보드 부팅 성공을 이번 후보의 부팅 성공으로 간주하지 않는다.

| 항목 | 결과 |
|---|---:|
| CPU / fabric / SD 최대 | 50 / 100 / 25 MHz |
| LUT / FF / BRAM / DSP | 114,075 / 74,189 / 101.5 / 62 |
| 점유 Slice | 32,792 / 33,450 (98.03%) |
| 배선 후 WNS / WHS | +0.034ns / +0.027ns |
| TNS / THS | 0 / 0 |
| CDC Warning·Critical | 0 |
| 최종 DRC | Error·Critical 0, 기존 MIG Warning 5건 |

클럭·0.300ns setup uncertainty를 유지했다. 원본 Vivado 로그의 Project 1-1108 Critical Warning은
incremental 실행 시간을 줄이려고 uncertainty를 무시하라는 제안이며 적용하지 않았다.
공식 MIG·HDMI IP 본문은 변경하지 않았다. 외부 수신기 I/O 검증 범위는 저장소 문서를 참조한다.

SD 응답·CRC·지연·오류, DMA 768개 무작위 descriptor, CPU 펌웨어의 SD/DMA·M/S 인터럽트,
보드 AXI→MIG 연결과 mock DDR를 포함한 CPU/BOSIO 회귀가 통과했다.
실제 이미지의 RTL 로더 payload 비교와 같은 payload의 QEMU BusyBox 복구 셸 검사도 통과했다.
QEMU에는 새 SD 장치 모델이 없으며, 전체 CPU RTL에서 Linux 셸까지 이어진 시험은 아직 완료하지 않았다.

## 첨부파일

- `ORYUKDO-KFB-SD4-DMA-v1.bit`: MIG·HDMI·SD4·DMA를 포함한 전체 보드 비트스트림.
- `ORYUKDO-KFB-SD4-DMA-v1.img`: 263MiB raw SD 이미지, 부팅 데이터와 256MiB ext4 `/data`.
- `ORYUKDO-SD4-DMA-rtl-software-tests.tar.gz`: 검증 당시 RTL·드라이버·테스트·문서 압축본.
- `linux-6.12-sd4-dma-source.tar.gz`: 실제 커널 빌드의 독립 Linux 전체 소스.
- `SD4-SHA256SUMS.txt`: 첨부파일 해시.

새 `.bit`와 `.img`를 반드시 한 쌍으로 사용한다. GitHub 자동 생성 소스 ZIP과 검증 당시 RTL 압축본은
포장 범위가 다르다. initramfs의 BusyBox를 유지하며 SD의 남는 공간 전체를 자동 확장하지 않는다.
보드 전원을 끄고 카드를 기록·검증한 뒤 사용한다. 카드 기록은 기존 카드 내용을 지운다.

## 다음 실보드 확인

Linux에서 MMC 카드 탐색, `/data` 마운트, `storage-check`, 재부팅 후 파일 보존, 실제 속도를 확인해야 한다.
raw 부트 로더는 기존 바이트 입력 경로이며, BoAYO 렌더링의 DMA 가속과 SD 연속 다중 블록 전송은 미구현이다.
이 릴리스는 Bash/Vim이나 SD를 루트 파일시스템으로 쓰는 구성으로 변경하지 않는다.

문서: https://github.com/VARZero/ORYUKDO-3d5i_BOSIO_SoC/tree/main/variants/sd4-dma

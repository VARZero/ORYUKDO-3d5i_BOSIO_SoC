# SD4/DMA 실보드 확인 순서

이 문서는 보드를 다시 연결할 때 수행할 절차다. 아직 수행한 결과가 아니다.
현재 작업에서는 SD 카드 기록, FPGA 업로드, UART 접속을 하지 않았다.

## 준비

공개 파일은 [SD4 사전 릴리스](https://github.com/VARZero/ORYUKDO-3d5i_BOSIO_SoC/releases/tag/sd4-dma-20261110-candidate)에서 받는다.
`SD4-SHA256SUMS.txt`로 다운로드 파일을 검사한다. 게시본의 결과·해시는
[provenance/board_manifest.json](provenance/board_manifest.json)과 [release_assets.json](provenance/release_assets.json)에 있다.
아래 `D:/temp/...`는 제작 당시 로컬 위치이며 다른 PC에서는 다운로드 위치로 바꾼다.

1. 2026-11-10 전체 보드 합성/배선과 비트스트림 생성은 완료했다. `validation/status.json`,
   `validation/board_implementation.json` 및 후보 폴더의 `board_manifest.json`을 확인한다.
   비트스트림은 `D:/temp/gen3bosio/sd4-dma/candidate/ORYUKDO-KFB-SD4-DMA-v1.bit`이다.
   아래 SD 이미지와 한 쌍이며, 이 문서의 실보드 절차는 아직 실행하지 않았다.
2. 기존 SD 내용을 보관한다. 새 이미지를 기록하면 기존 카드의 데이터가 지워진다.
   후보 이미지는 `D:/temp/gen3bosio/sd4-dma/candidate/ORYUKDO-KFB-SD4-DMA-v1.img`이다.
3. 대응 비트스트림과 이미지의 해시를 확인한 뒤 이미지를 SD에 기록·검증한다.
   SD 카드를 교체할 때는 보드 전원을 끈다. SPI 모드로 동작하던 카드도 전원을 껐다 켜야 한다.
4. 보드 전원을 켜고 대응 비트스트림을 올린다. 기존 SPI 전용 비트스트림은 새 Linux SD 호스트와 호환되지 않는다.

## Linux에서 확인

부팅 로그에서 MMC 카드 탐색, `mmcblk0: p1 p2`, `ORYUKDO: SD ext4 /data mounted`를 확인한다.
마운트 실패 메시지가 나오면 복구 셸 접근만 된 상태이며 영구 저장 성공이 아니다.

```sh
cat /etc/oryukdo-image
cat /proc/partitions
cat /proc/interrupts
cat /proc/mounts
storage-check
ddrcheck
```

`storage-check`는 실제 ext4 마운트 여부, 256KiB 파일 쓰기, sync 및 캐시를 비운 뒤 읽기 해시 일치를 확인한다.
실행 전후 `/proc/interrupts`에서 SD 인터럽트 수가 증가하는지도 확인한다.
`ddrcheck`는 상위 메모리 검사이며 SD DMA의 상위 주소 전체 검증을 대신하지 않는다.

영구 보존 검사는 별도로 한다.

```sh
echo ORYUKDO_SD4_PERSISTENCE > /data/persistence-check.txt
sync
sha256sum /data/persistence-check.txt
```

파일시스템을 정상 해제한 뒤 전원을 껐다 켜고, 비트스트림을 다시 올려 같은 파일과 해시를 확인한다.
전원을 끄기 전 `/data`를 사용하는 프로그램을 종료하고 다음 명령의 성공을 확인한다.

```sh
cd /
sync
umount /data
```

아직 실행 중인 프로그램이 있으면 unmount가 실패할 수 있다. 실패 상태에서 성공으로 기록하지 않는다.
의도적인 전원 차단 복구 시험과 정상 종료 후 보존 시험은 구분한다.

## 성능과 남은 범위

* 읽기/쓰기 실제 시간과 CPU 사용률을 함께 측정한다. 단일 블록 명령 및 coherent bounce 복사가 남아 있다.
* SD 4비트/25MHz의 이론치 12.5MB/s를 실제 파일시스템 성능으로 쓰지 않는다.
* DMAengine memcpy/memset은 드라이버가 등록된 상태다. 별도 kernel client/dmatest로 실보드 실행을 확인해야 한다.
* BoAYO의 초기 기하 계산과 업로드 경로는 이번 작업에서 DMA로 바꾸지 않았다.
* 실행 중 SD 카드를 빼거나 끼우는 동작은 지원하지 않는다.

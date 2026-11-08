# 라이선스와 외부 소스

이 저장소에는 서로 다른 라이선스의 구성 요소가 있다. 저장소 전체를 하나의 라이선스로 재지정하지 않는다. 원본 저작권 및 라이선스 고지는 그대로 보존한다.

| 구성 요소 | 출처와 고지 |
|---|---|
| ORYUKDO 스케줄러 | VARZero/ORYUKDO, 기존 Apache-2.0 고지 `LICENSES/ORYUKDO-Apache-2.0.txt` |
| BOSIO 투영·출력·센서 | 각 `soc/vendor/*/LICENSE`의 Apache-2.0 고지 |
| 공식 Digilent rgb2dvi | `soc/board/vendor/digilent_rgb2dvi/`, BSD 고지와 upstream 해시 유지 |
| 비교용 Puzhi HDMI 원본 | `soc/board/vendor/hdmi/`, 원본 보존 및 별도 무결성 검사, 실제 빌드에는 사용하지 않음 |
| AMD MIG / XPM | 설치된 Vivado에서 생성·참조. 생성 RTL과 Vivado 라이브러리를 이 저장소에 재배포하지 않음 |
| Linux 6.12 | GPL-2.0-only 및 Linux syscall 예외, `LICENSES/Linux-*`, 전체 소스의 개별 SPDX 고지 |
| BusyBox 1.37.0 | GPL-2.0, `LICENSES/BusyBox-GPL-2.0`, 고정 버전 소스 다운로드와 빌드 설정 포함 |
| musl 1.2.5 | `LICENSES/musl-COPYRIGHT` |
| OpenSBI v1.8.1 | BSD-2-Clause 계열 및 개별 원본 고지, `LICENSES/OpenSBI-BSD.txt` |

Linux 원본 URL·해시는 `software/linux/source_manifest.json`, BusyBox·musl 원본 URL·해시는 `software/userspace/build_busybox.sh`, OpenSBI 저장소·커밋은 `provenance/firmware_origin.json`에 있다. 원본 및 수정 소스를 확보할 수 있도록 빌드 입력과 설정을 함께 제공한다.

새 SoC 연결·CPU·보드 어댑터 파일에 별도의 배포 라이선스를 추가하려면 저장소 소유자의 선택이 필요하다. 게시 준비 과정에서는 기존 고지의 적용 범위를 임의로 확장하지 않았다. 제3자 원본 설명과 라이선스는 번역으로 대체하지 않는다.

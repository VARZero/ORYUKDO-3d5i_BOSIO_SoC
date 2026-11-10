# 근거 자료의 기준

이 디렉터리의 기존 JSON 파일은 2026-11-08 최초 실보드 검증본의 기록이다.
특히 `package_files.json`은 최초 게시 당시 파일 해시 목록이며 이후 문서 추가분까지 포함하는 최신 저장소 manifest가 아니다.
루트 RTL·Linux·펌웨어의 기존 검사는 `scripts/verify_sources.py`를 사용한다.

2026-11-10 SD4·DMA 후보의 근거는 `variants/sd4-dma/provenance/`와
`variants/sd4-dma/validation/`, `variants/sd4-dma/evidence/board/`에 있다.
게시본 전체 파일은 `scripts/verify_sd4_publication.py`로 확인한다.

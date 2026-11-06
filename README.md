# PadMac

DualSense(PS5) 패드로 macOS를 조작하는 메뉴바 앱.

## 버튼 매핑

| 버튼 | 동작 |
|---|---|
| 왼쪽 스틱 | 마우스 이동 (기울인 정도에 따라 속도 변화) |
| 오른쪽 스틱 | 스크롤 (세로/가로) |
| L1 / R1 | 우클릭 / 좌클릭 (누른 채 이동하면 드래그) |
| L2 / R2 | 왼쪽 / 오른쪽 Space로 이동 (⌃← / ⌃→) |
| L3 / R3 | 뒤로 / 앞으로 (⌘[ / ⌘]) |
| ✕ / ○ | 복사 / 붙여넣기 (⌘C / ⌘V) |
| □ / △ | 실행 취소 / 다시 실행 (⌘Z / ⌘⇧Z) |
| 방향키 | 화살표 키 (누르고 있으면 반복) |
| Options (≡) | 기능 켜기/끄기 (라이트바: 파랑 = 켜짐, 주황 = 꺼짐) |

## 빌드 & 실행

macOS 13 이상, Apple Silicon, Xcode Command Line Tools 필요.

```sh
./build.sh                       # ~/Applications/PadMac.app 으로 설치
open ~/Applications/PadMac.app
```

처음 실행하면 **시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용**에서 PadMac을 허용해야 합니다.

다시 빌드한 뒤 입력이 안 먹히면 (ad-hoc 서명이 바뀌어 권한이 무효화됨):

```sh
tccutil reset Accessibility com.sonbumsu.padmac
pkill -x PadMac; open ~/Applications/PadMac.app
```

## 구조

- `Sources/PadMac/PadEngine.swift` — GameController로 패드 입력을 120Hz로 읽어 동작으로 변환
- `Sources/PadMac/Synth.swift` — CGEvent로 마우스/스크롤/키 이벤트 생성
- `Sources/PadMac/AppDelegate.swift` — 메뉴바 아이콘과 메뉴
- `build.sh` — `swiftc`로 컴파일하고 `.app` 번들 생성 및 ad-hoc 서명

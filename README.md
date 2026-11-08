<p align="center">
  <img src="assets/logo.png" width="160" alt="PadMac 로고">
</p>

<h1 align="center">PadMac</h1>

<p align="center">DualSense(PS5) 패드로 macOS를 조작하는 메뉴바 앱</p>

## 버튼 설정

메뉴바 🎮 아이콘 → **버튼 설정…** 에서 버튼마다 동작을 바꿀 수 있습니다.

- 버튼마다 **기본** 동작과 **L2 누른 채** 동작을 따로 지정
- 목록에서 고르거나(클릭, Space 이동, Mission Control, 앱 전환, 자주 쓰는 단축키), **단축키 직접 입력…** 으로 원하는 키 조합을 눌러서 녹화
- 마우스 속도, 스크롤 속도, 스크롤 방향
- 바꾸면 바로 적용되고 `~/Library/Application Support/PadMac/config.json` 에 저장됨 (백업·공유 가능)

왼쪽 스틱(마우스), 오른쪽 스틱(스크롤), Options(켜기/끄기)는 고정입니다.

## 기본 버튼 매핑

### 기본

| 버튼 | 동작 |
|---|---|
| 왼쪽 스틱 | 마우스 이동 (기울인 정도에 따라 속도 변화) |
| 오른쪽 스틱 | 스크롤 (세로/가로) |
| L1 / R1 | 우클릭 / 좌클릭 (누른 채 이동하면 드래그) |
| L2 / R2 | 왼쪽 / 오른쪽 Space로 이동 (⌃← / ⌃→). L2는 짧게 눌렀다 뗄 때 동작 |
| L3 / R3 | 축소 / 확대 (⌘- / ⌘+) |
| ✕ / ○ | Return / Esc |
| □ / △ | 탭 닫기 / 새 탭 (⌘W / ⌘T) |
| 방향키 | 화살표 키 (누르고 있으면 반복) |
| Create | Spotlight (⌘Space) |
| PS | Mission Control |
| 터치패드 클릭 | 앱 전환 (⌘Tab). 빠르게 여러 번 누르면 다음 앱으로 |
| Options (≡) | 기능 켜기/끄기 (라이트바: 파랑 = 켜짐, 주황 = 꺼짐) |

### L2를 누른 채로 (편집 레이어)

| 버튼 | 동작 |
|---|---|
| ✕ / ○ | 복사 / 붙여넣기 (⌘C / ⌘V) |
| □ / △ | 실행 취소 / 다시 실행 (⌘Z / ⌘⇧Z) |
| ← / → | 뒤로 / 앞으로 (⌘[ / ⌘]) |

> PS 버튼은 macOS가 기본으로 가로채서 Launchpad를 엽니다. **시스템 설정 → 게임 컨트롤러**에서 해당 동작을 꺼 주세요.

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

- `Sources/PadMac/PadEngine.swift` — GameController로 패드 입력을 120Hz로 읽어 설정에 따라 동작으로 변환
- `Sources/PadMac/Config.swift` — 버튼·동작·설정 모델과 저장 (config.json)
- `Sources/PadMac/SettingsView.swift` — 버튼 설정 창 (SwiftUI)
- `Sources/PadMac/Synth.swift` — CGEvent로 마우스/스크롤/키 이벤트 생성
- `Sources/PadMac/AppDelegate.swift` — 메뉴바 아이콘과 메뉴
- `build.sh` — `swiftc`로 컴파일하고 `.app` 번들 생성 및 ad-hoc 서명

## 아이콘 다시 만들기

`assets/logo-source.png` 를 바꾼 뒤 프로젝트 루트에서:

```sh
swiftc -O tools/make_icons.swift -o /tmp/make_icons && /tmp/make_icons
./build.sh
```

`assets/logo.png`(README 로고), `assets/AppIcon.icns`(앱 아이콘), `assets/MenuBarIcon.png`(메뉴바 아이콘)가 새로 만들어집니다.

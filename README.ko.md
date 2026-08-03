# Hitomi Badayo

<p align="center">
  <a href="README.md"><kbd>English</kbd></a>
  <a href="README.ja.md"><kbd>日本語</kbd></a>
  <a href="README.zh-Hans.md"><kbd>简体中文</kbd></a>
  <a href="README.zh-Hant.md"><kbd>繁體中文</kbd></a>
  <strong><a href="README.ko.md"><kbd>한국어</kbd></a></strong>
</p>

Hitomi Badayo는 Apple Silicon Mac용 네이티브 다운로드 관리자입니다. 대기열 중심의 macOS 인터페이스에서 소스별 이름과 저장 폴더, 인증, 미리보기, 압축, 미디어 다운로드 작업을 함께 관리할 수 있습니다.

이 앱은 기존 데스크톱 다운로더에서 관찰한 동작을 참고해 독립적으로 네이티브 구현한 프로그램입니다. 원본 실행 파일이나 디컴파일된 바이트코드는 이 저장소에 포함되어 있지 않습니다.

버전 0.5.0에서는 0.4.2의 사용자 동작, 설정, 저장 데이터, 다운로드 결과를 유지하면서 장기 유지보수를 위한 리팩터링을 완료했습니다.

## 주요 기능

- SwiftUI와 AppKit으로 만든 macOS 네이티브 인터페이스
- 순서 변경, 취소, 재시도, 항목별 진행률을 지원하는 동시 작업 대기열
- Hitomi, Pixiv, YouTube, Kemono 계열 아카이브, Booru 계열 사이트와 기타 소스를 위한 전용 처리기
- 소스별 출력 폴더, 이름 템플릿, ZIP 및 CBZ 옵션
- 로그인이 필요한 소스를 위한 내장 로그인 창과 로컬 쿠키 저장
- 로컬 루프백에서만 동작하는 SpoofDPI 프록시를 통한 선택형 앱 전용 또는 앱·브라우저 DPI 우회
- 썸네일 미리보기, 다운로드 결과 열기, 라이브 녹화 안전 종료 및 정리 기능
- 영어, 일본어, 중국어 간체, 중국어 번체, 한국어 인터페이스

소스 사이트의 동작은 수시로 바뀔 수 있습니다. 한 릴리스에서 작동한 처리기도 사이트 변경에 따라 유지보수가 필요할 수 있습니다.

## 시스템 요구 사항

- Apple Silicon Mac(arm64)
- macOS 14 Sonoma 이상
- 온라인 소스 연결과 선택형 보조 도구 설치를 위한 인터넷 연결

## 릴리스 설치

1. 해당 GitHub Release에서 `Hitomi-Badayo-macOS.zip`을 다운로드합니다.
2. 압축을 풀고 필요한 경우 `Hitomi Badayo.app`을 응용 프로그램 폴더로 옮깁니다.
3. 처음 실행할 때 앱을 Control-클릭하고 **열기**를 선택합니다.
4. macOS가 계속 실행을 차단하면 **시스템 설정 > 개인정보 보호 및 보안 > 확인 없이 열기**를 사용합니다.

배포 앱은 임시 서명되어 있으며 Developer ID 서명이나 Apple 공증을 받지 않았습니다. Gatekeeper를 시스템 전체에서 비활성화하지 마세요. 데이터 저장 위치와 최초 실행 절차는 [INSTALLATION.md](docs/INSTALLATION.md)에서 확인할 수 있습니다.

## 소스에서 빌드

Xcode 명령어 라인 도구를 설치한 다음 아래 명령을 실행합니다.

```sh
xcode-select --install
./build.sh
```

앱은 `Build/Hitomi Badayo.app`에 생성됩니다. 다른 출력 디렉터리를 사용하려면 다음과 같이 실행합니다.

```sh
./build.sh Build-Local
```

빌드는 시스템 macOS SDK를 사용하며 Xcode 프로젝트는 필요하지 않습니다.

## 외부 도구

Apple Silicon용 aria2 1.37.0과 SpoofDPI 1.5.3은 라이선스 정보와 함께 별도의 보조 프로세스로 앱에 포함됩니다. yt-dlp, Deno, FFmpeg, ffprobe는 선택형 도구이며 사용자가 관리 도구 설치를 요청한 경우에만 다운로드됩니다. YouTube의 JavaScript 검증을 처리할 수 있도록 Deno는 yt-dlp에 직접 전달됩니다. 자세한 내용은 [THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md)를 확인하세요.

## DPI 우회

선택 기능은 **설정 > 네트워크 > DPI 우회**에 있으며 기본값은 **꺼짐**입니다. **앱만**은 macOS 프록시 설정을 변경하거나 관리자 권한을 요청하지 않고, 지원되는 Hitomi Badayo 다운로드를 `127.0.0.1`의 SpoofDPI로 연결합니다. **앱 및 브라우저**는 현재 사용 중인 macOS 웹 프록시(HTTP)와 보안 웹 프록시(HTTPS)도 설정하므로 관리자 승인이 필요합니다. 앱은 기존 시스템 프록시 값을 저장하고 이 모드를 끄거나 앱을 종료할 때 복원합니다.

수동 프록시 설정은 별도로 저장됩니다. DPI 우회와 수동 프록시를 모두 켜면 로컬 SpoofDPI 경로가 우선하며, 수동 프록시 설정은 그대로 보존되었다가 DPI 우회를 끄면 다시 적용됩니다.

## 데이터 및 개인정보 보호

대기열 상태, 설정, 로그인 쿠키, 보조 도구, 다운로드 결과는 사용자의 Mac에 저장됩니다. 프로젝트에서 운영하는 원격 측정 서비스는 없습니다. 네트워크 요청은 사용자가 선택한 소스 사이트와 선택형 도구 제공자에게 전송될 수 있습니다. 정확한 저장 위치와 제한 사항은 [PRIVACY.md](docs/PRIVACY.md)를 확인하세요.

## 책임 있는 사용

접근하고 보관할 권한이 있는 자료에만 이 앱을 사용하세요. 다운로드에 적용되는 저작권, 계정, 구독 및 소스 사이트 이용 약관을 확인할 책임은 사용자에게 있습니다. 이 프로젝트는 지원 사이트와 제휴 관계가 없으며, 사이트 이름과 표시는 각 소유자의 자산입니다.

## 프로젝트 문서

아래 문서는 현재 영어로 관리됩니다.

- [INSTALLATION.md](docs/INSTALLATION.md): 설치와 최초 실행 동작
- [CHANGELOG.md](docs/CHANGELOG.md): 릴리스 기록
- [PRIVACY.md](docs/PRIVACY.md): 로컬 데이터 및 네트워크 동작
- [SECURITY.md](docs/SECURITY.md): 보안 취약점 신고 안내
- [THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md): 내장 및 선택형 외부 도구

## 라이선스

Hitomi Badayo 프로젝트 소스는 [MIT License](LICENSE)로 배포됩니다. 내장 및 선택형 외부 구성 요소에는 [THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md)에 기록된 각 라이선스가 그대로 적용됩니다.

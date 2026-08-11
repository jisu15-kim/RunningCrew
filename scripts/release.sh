#!/usr/bin/env bash
# RunningCrew 릴리스 파이프라인 (Mding scripts/release.sh 패턴)
#   빌드 → Developer ID 서명 → DMG → 공증(notarization) → 스테이플
#
# 사용법:
#   ./scripts/release.sh          # Developer ID 서명 + 공증 (배포용)
#   ./scripts/release.sh --adhoc  # ad-hoc 서명 DMG (개인용/테스트, 공증 없음)
#
# 선행 조건 (배포용, 최초 1회):
#   1. Xcode 에 Developer ID Application 인증서 발급
#   2. 공증 자격증명을 키체인 프로필로 저장:
#        xcrun notarytool store-credentials runningcrew-notary \
#          --apple-id <애플개발자계정이메일> --team-id 846TMZL7WC
#      (암호는 https://account.apple.com ▸ 로그인 및 보안 ▸ 앱 암호 에서 생성한 앱 암호)
#
# 버전 올리기: Xcode 타겟 설정의 MARKETING_VERSION (pbxproj) 수정 후 실행
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="RunningCrew"
SCHEME="RunningCrew"
SIGN_IDENTITY="Developer ID Application: Jisu Kim (846TMZL7WC)"
NOTARY_PROFILE="${NOTARY_PROFILE:-runningcrew-notary}"
RELEASE_DIR="$REPO_ROOT/.release"

ADHOC=0
[[ "${1:-}" == "--adhoc" ]] && ADHOC=1

VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$APP_NAME.xcodeproj/project.pbxproj" | head -1)
[[ -n "$VERSION" ]] || { echo "✗ pbxproj 에서 MARKETING_VERSION 을 읽지 못했습니다"; exit 1; }
DMG="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"

echo "▸ $APP_NAME $VERSION 릴리스 시작$([[ $ADHOC == 1 ]] && echo ' (ad-hoc)')"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# 1) Release 아카이브 ---------------------------------------------------------
echo "▸ Release 아카이브"
ARCHIVE_ARGS=()
if [[ $ADHOC == 1 ]]; then
    ARCHIVE_ARGS=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="")
fi
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$RELEASE_DIR/$APP_NAME.xcarchive" archive \
    ${ARCHIVE_ARGS[@]+"${ARCHIVE_ARGS[@]}"} \
    >"$RELEASE_DIR/archive.log" 2>&1 \
    || { tail -30 "$RELEASE_DIR/archive.log"; exit 1; }

# 2) 앱 추출 (배포 모드는 Developer ID 로 재서명 export) ------------------------
if [[ $ADHOC == 1 ]]; then
    APP="$RELEASE_DIR/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app"
else
    echo "▸ Developer ID export"
    xcodebuild -exportArchive \
        -archivePath "$RELEASE_DIR/$APP_NAME.xcarchive" \
        -exportOptionsPlist scripts/ExportOptions.plist \
        -exportPath "$RELEASE_DIR/export" \
        >"$RELEASE_DIR/export.log" 2>&1 \
        || { tail -30 "$RELEASE_DIR/export.log"; exit 1; }
    APP="$RELEASE_DIR/export/$APP_NAME.app"
    codesign --verify --deep --strict "$APP"
fi
[[ -d "$APP" ]] || { echo "✗ 앱을 찾지 못했습니다: $APP"; exit 1; }

# 3) DMG 패키징 ---------------------------------------------------------------
echo "▸ DMG 생성"
command -v create-dmg >/dev/null || brew install create-dmg
STAGE="$RELEASE_DIR/dmg-stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
# 배경: 1x·2x PNG 를 멀티해상도 TIFF 로 합쳐 레티나 대응.
# 원본 PNG 는 scripts/generate_dmg_background.swift 로 생성·커밋되어 있다.
tiffutil -cathidpicheck scripts/dmg-assets/dmg-background.png scripts/dmg-assets/dmg-background@2x.png \
    -out "$RELEASE_DIR/dmg-background.tiff" 2>/dev/null
VOLICON_ARGS=()
[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] \
    && VOLICON_ARGS=(--volicon "$APP/Contents/Resources/AppIcon.icns")
create-dmg \
    --volname "$APP_NAME $VERSION" \
    ${VOLICON_ARGS[@]+"${VOLICON_ARGS[@]}"} \
    --background "$RELEASE_DIR/dmg-background.tiff" \
    --window-pos 200 150 \
    --window-size 660 420 \
    --icon-size 128 \
    --text-size 13 \
    --icon "$APP_NAME.app" 165 190 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 495 190 \
    "$DMG" "$STAGE"

# 4) DMG 서명 + 공증 -----------------------------------------------------------
if [[ $ADHOC == 1 ]]; then
    echo "⚠️  ad-hoc DMG — 서명·공증이 없어 다른 머신에서는 Gatekeeper 경고가 떠요 (개인용)"
else
    # DMG 컨테이너도 서명해야 spctl(Gatekeeper) 평가를 통과한다.
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "▸ 공증 제출 (Apple 서버 대기, 수 분 소요)"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
        xcrun stapler validate "$DMG"
        spctl -a -t open --context context:primary-signature "$DMG"
        echo "✓ 공증·스테이플 완료"
    else
        echo "⚠️  공증 프로필 '$NOTARY_PROFILE' 없음 — 공증을 건너뜁니다."
        echo "   배포하려면 파일 상단 주석의 store-credentials 명령으로 프로필을 만든 뒤 다시 실행하세요."
    fi
fi

echo ""
echo "✓ 완료: $DMG"

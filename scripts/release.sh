#!/usr/bin/env bash
# RunningCrew 릴리스 파이프라인 (Mding scripts/release.sh 패턴)
#   빌드 → Developer ID 서명 → DMG → 공증 → 스테이플 → appcast 갱신 → GitHub Release → Homebrew tap
#
# 사용법:
#   ./scripts/release.sh          # 전체 릴리스 (서명 + 공증 + 배포)
#   ./scripts/release.sh --adhoc  # ad-hoc 서명 DMG 만 생성 (개인용/테스트, 배포 단계 없음)
#
# 선행 조건 (최초 1회):
#   1. Xcode 에 Developer ID Application 인증서 발급
#   2. 공증 자격증명을 키체인 프로필로 저장:
#        xcrun notarytool store-credentials runningcrew-notary \
#          --apple-id <애플개발자계정이메일> --team-id 846TMZL7WC
#   3. gh auth login (GitHub Release 생성용)
#
# 릴리스 절차:
#   1. pbxproj 의 MARKETING_VERSION (예: 1.1.0) 과
#      CURRENT_PROJECT_VERSION (정수, 릴리스마다 +1 — Sparkle 버전 비교 기준) 을 올리고 커밋
#   2. ./scripts/release.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="RunningCrew"
SCHEME="RunningCrew"
REPO="jisu15-kim/RunningCrew"
SIGN_IDENTITY="Developer ID Application: Jisu Kim (846TMZL7WC)"
NOTARY_PROFILE="${NOTARY_PROFILE:-runningcrew-notary}"
SPARKLE_BIN="$REPO_ROOT/.tools/sparkle/bin"
RELEASE_DIR="$REPO_ROOT/.release"

ADHOC=0
[[ "${1:-}" == "--adhoc" ]] && ADHOC=1

PBXPROJ="$APP_NAME.xcodeproj/project.pbxproj"
VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$PBXPROJ" | head -1)
BUILD_NUM=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);.*/\1/p' "$PBXPROJ" | head -1)
[[ -n "$VERSION" && -n "$BUILD_NUM" ]] || { echo "✗ pbxproj 에서 버전을 읽지 못했습니다"; exit 1; }

TAG="v$VERSION"
DMG="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"

echo "▸ $APP_NAME $VERSION (build $BUILD_NUM) 릴리스 시작$([[ $ADHOC == 1 ]] && echo ' (ad-hoc)')"

# 0) 사전 점검 (배포 모드만) -----------------------------------------------------
if [[ $ADHOC == 0 ]]; then
    [[ -z "$(git status --porcelain)" ]] \
        || { echo "✗ 작업 트리가 clean 하지 않습니다. 커밋 후 다시 실행하세요."; exit 1; }
    git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
        && { echo "✗ 태그 $TAG 가 이미 존재합니다. MARKETING_VERSION 을 올리세요."; exit 1; }
    if [[ -f appcast.xml ]] && grep -q "<sparkle:version>$BUILD_NUM</sparkle:version>" appcast.xml; then
        echo "✗ build $BUILD_NUM 이 이미 appcast 에 있습니다. CURRENT_PROJECT_VERSION 을 올리세요."
        exit 1
    fi
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || { echo "✗ 공증 프로필 '$NOTARY_PROFILE' 없음 — 파일 상단의 store-credentials 명령을 먼저 실행하세요."; exit 1; }

    # Sparkle CLI 도구(appcast 생성·서명) — 없으면 최신 릴리스에서 다운로드
    if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
        echo "▸ Sparkle CLI 도구 다운로드"
        SPARKLE_TAG=$(curl -sL https://api.github.com/repos/sparkle-project/Sparkle/releases/latest \
            | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p' | head -1)
        mkdir -p "$REPO_ROOT/.tools/sparkle"
        curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_TAG/Sparkle-$SPARKLE_TAG.tar.xz" \
            | tar -xJ -C "$REPO_ROOT/.tools/sparkle" bin
    fi
fi

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

if [[ $ADHOC == 1 ]]; then
    echo "⚠️  ad-hoc DMG — 서명·공증이 없어 다른 머신에서는 Gatekeeper 경고가 떠요 (개인용)"
    echo ""
    echo "✓ 완료: $DMG"
    exit 0
fi

# 4) DMG 서명 + 공증 -----------------------------------------------------------
# DMG 컨테이너도 서명해야 spctl(Gatekeeper) 평가를 통과한다.
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
echo "▸ 공증 제출 (Apple 서버 대기, 수 분 소요)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature "$DMG"
echo "✓ 공증·스테이플 완료"

# 5) appcast 갱신 (Sparkle 자동 업데이트 피드) ---------------------------------
echo "▸ appcast.xml 갱신"
UPDATES="$RELEASE_DIR/updates"
mkdir -p "$UPDATES"
cp "$DMG" "$UPDATES/"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    -o "$REPO_ROOT/appcast.xml" \
    "$UPDATES"

# 6) appcast 커밋·푸시 → GitHub Release 게시 -----------------------------------
# 반드시 push 가 먼저다 — gh release create 는 태그를 "원격 main 의 현재 HEAD" 에
# 만들므로, push 전에 실행하면 태그가 한 릴리스 이전 커밋에 붙는다.
echo "▸ GitHub Release 게시"
git add appcast.xml
git commit -m "release: $TAG"
git push origin main
gh release create "$TAG" "$DMG" --title "$APP_NAME $VERSION" --generate-notes --target "$(git rev-parse HEAD)"

# 7) Homebrew tap cask 갱신 ----------------------------------------------------
echo "▸ Homebrew tap cask 갱신"
TAP_REPO="jisu15-kim/homebrew-tap"
SHA256=$(shasum -a 256 "$DMG" | awk '{print $1}')
CASK_FILE="$RELEASE_DIR/runningcrew.rb"
cat >"$CASK_FILE" <<EOF
cask "runningcrew" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$REPO/releases/download/v#{version}/$APP_NAME-#{version}.dmg"
  name "RunningCrew"
  desc "Menu bar app for managing GitHub self-hosted runners"
  homepage "https://github.com/$REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :tahoe

  app "RunningCrew.app"

  zap trash: [
    "~/Library/Caches/com.jisukim.running-crew.RunningCrew",
    "~/Library/HTTPStorages/com.jisukim.running-crew.RunningCrew",
    "~/Library/Logs/RunningCrew",
    "~/Library/Preferences/com.jisukim.running-crew.RunningCrew.plist",
    "~/Library/Saved Application State/com.jisukim.running-crew.RunningCrew.savedState",
  ]
end
EOF
EXISTING_SHA=$(gh api "repos/$TAP_REPO/contents/Casks/runningcrew.rb" --jq .sha 2>/dev/null || true)
gh api -X PUT "repos/$TAP_REPO/contents/Casks/runningcrew.rb" \
    -f message="runningcrew $VERSION" \
    -f content="$(base64 -i "$CASK_FILE")" \
    ${EXISTING_SHA:+-f sha="$EXISTING_SHA"} >/dev/null
echo "✓ tap 갱신: https://github.com/$TAP_REPO"

echo ""
echo "✓ $APP_NAME $VERSION 릴리스 완료"
echo "  https://github.com/$REPO/releases/tag/$TAG"

#!/bin/bash
# mobai_install.sh
# flutter run がカスタムデバイス向けに flutter_assets を渡してくる場合、
# mobai ios_builder がビルドした dist/*.ipa を代わりにインストールする

set -e

LOCAL_PATH="$1"
echo "[mobai_install] called with: $LOCAL_PATH" >&2

BUILDER_URL="${MOBAI_URL:-http://YUZU-SURFACE.local:8686}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "$LOCAL_PATH" == *"flutter_assets"* ]]; then
  # flutter run (debug) は flutter_assets を渡してくるため、
  # mobai ios_builder がビルドした dist/*.ipa を使用する
  IPA_PATH=$(find "$REPO_ROOT/flutter_app/dist" -name "*.ipa" -type f 2>/dev/null | sort | tail -1)
  if [ -z "$IPA_PATH" ]; then
    echo "[mobai_install] Error: No IPA found in $REPO_ROOT/dist/" >&2
    exit 1
  fi
  echo "[mobai_install] using IPA: $IPA_PATH" >&2
else
  IPA_PATH="$LOCAL_PATH"
  echo "[mobai_install] using IPA: $IPA_PATH" >&2
fi

# MobAIサーバーはWindows上で動作するため、WSLパスをWindowsパスに変換する
WIN_IPA_PATH=$(wslpath -w "$IPA_PATH")
echo "[mobai_install] windows path: $WIN_IPA_PATH" >&2

/usr/local/bin/builder mobai --url "$BUILDER_URL" install "$WIN_IPA_PATH"
echo "[mobai_install] done" >&2

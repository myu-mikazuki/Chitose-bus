#!/bin/bash
# dev_flutter.sh
# scripts/flutter ラッパーを PATH に差し込んだ上で builder dev flutter を実行する
# これにより builder が内部で呼ぶ flutter attach に --dart-define-from-file が付与される

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

chmod +x "$SCRIPT_DIR/flutter"

exec env PATH="$SCRIPT_DIR:$PATH" /usr/local/bin/builder dev flutter "$@"

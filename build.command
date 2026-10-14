#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
finish() {
  result=$?
  if [ "$result" -ne 0 ]; then
    echo
    echo 'Сборка остановилась. Пришлите текст ошибки выше или файл .build/build.log.'
  fi
  if [ -t 0 ]; then read -r -p 'Нажмите Enter, чтобы закрыть окно...' || true; fi
}
trap finish EXIT
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo 'Не найден компилятор Swift. В Терминале выполните xcode-select --install, завершите установку и снова откройте этот файл.'
  exit 1
fi
mkdir -p .build dist
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macosx13.0"
echo 'Сначала проверяем работу с базой на временной копии…'
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK_PATH" -target "$TARGET" \
  Sources/Store.swift Sources/Report.swift Tests/CoreChecks.swift -framework AppKit -lsqlite3 -o .build/core-checks 2>&1 | tee .build/build.log
.build/core-checks "$PWD/Resources/warehouse.db" 2>&1 | tee -a .build/build.log
echo 'Собираем нативное приложение…'
xcrun swiftc -swift-version 5 -parse-as-library -O -sdk "$SDK_PATH" -target "$TARGET" \
  Sources/Store.swift Sources/Interface.swift Sources/Report.swift -framework SwiftUI -framework AppKit -lsqlite3 \
  -o .build/SkladNative 2>&1 | tee -a .build/build.log
APP='dist/Склад Native.app'
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/SkladNative "$APP/Contents/MacOS/SkladNative"
cp Resources/AppIcon.icns Resources/warehouse.db "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SkladNative</string>
<key>CFBundleIdentifier</key><string>org.coursework.sklad.native</string>
<key>CFBundleName</key><string>Склад Native</string>
<key>CFBundleDisplayName</key><string>Склад Native</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleShortVersionString</key><string>1.2</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" 'dist/Склад-Native-macOS.zip'
echo 'Готово. Откройте «Склад Native.app». При желании перенесите её в «Программы».'
open dist

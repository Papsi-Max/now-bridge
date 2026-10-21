#!/bin/zsh
# Builds build/NowBridge.app (ad hoc signed, not notarized).
set -e
cd "${0:A:h}"
swift build -c release
APP=build/NowBridge.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp "$(swift build -c release --show-bin-path)/NowBridge" $APP/Contents/MacOS/NowBridge
cp Info.plist $APP/Contents/
cp Resources/AppIcon.icns $APP/Contents/Resources/
codesign --force --sign - $APP
echo "OK → $APP"

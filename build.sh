#!/bin/zsh
# Builds build/NowBridge.app (ad hoc signed, not notarized).
set -e
cd "${0:A:h}"
ARCHS=()
[[ -n "$UNIVERSAL" ]] && ARCHS=(--arch arm64 --arch x86_64)   # UNIVERSAL=1 ./build.sh
swift build -c release $ARCHS
APP=build/NowBridge.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp "$(swift build -c release $ARCHS --show-bin-path)/NowBridge" $APP/Contents/MacOS/NowBridge
cp Info.plist $APP/Contents/
cp Resources/AppIcon.icns $APP/Contents/Resources/
codesign --force --sign - $APP
echo "OK → $APP"

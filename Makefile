APPNAME=NextEvt
SUPPORTFILES=./${APPNAME}/
BUILD_DIRECTORY = ./.build
RELEASE_DIRECTORY = ${BUILD_DIRECTORY}/apple/Products/Release
APP_DIRECTORY=${RELEASE_DIRECTORY}/${APPNAME}.app
APP_CONTENTS="${APP_DIRECTORY}/Contents"
CFBUNDLEEXECUTABLE=${APPNAME}
VERSION=`git tag | sort -V | tail -1 | cut -c2-`

install: build icon bundle codesign

build: 
	swift build -c release --arch arm64 --arch x86_64

icon:
	rm -rf ${BUILD_DIRECTORY}/Icon.iconset
	mkdir ${BUILD_DIRECTORY}/Icon.iconset
	sips -z 16 16 Icon512.png --out ${BUILD_DIRECTORY}/Icon.iconset/icon_16x16.png
	sips -z 32 32 Icon512.png --out ${BUILD_DIRECTORY}/Icon.iconset/icon_16x16@2x.png
	sips -z 32 32 Icon512.png --out ${BUILD_DIRECTORY}/Icon.iconset/icon_32x32.png
	sips -z 64 64 Icon512.png --out ${BUILD_DIRECTORY}/Icon.iconset/icon_32x32@2x.png
	sips -z 128 128 Icon512.png --out ${BUILD_DIRECTORY}/Icon.iconset/icon_128x128.png
	sips -z 256 256 Icon512.png --out ${BUILD_DIRECTORY}/Icon.iconset/icon_128x128@2x.png
	sips -z 256 256 Icon512.png --out ${BUILD_DIRECTORY}/Icon.iconset/icon_256x256.png
	sips -z 512 512 Icon512.png --out ${BUILD_DIRECTORY}/Icon.iconset/icon_256x256@2x.png
	sips -z 512 512 Icon512.png --out ${BUILD_DIRECTORY}/Icon.iconset/icon_512x512.png
	iconutil -c icns ${BUILD_DIRECTORY}/Icon.iconset

bundle:
	rm -rf ${APP_CONTENTS}
	mkdir -p "${APP_CONTENTS}/MacOS/"
	mkdir -p "${APP_CONTENTS}/Resources/"
	cp ${SUPPORTFILES}/Info.plist ${APP_CONTENTS}
	/usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion en-IT" ${APP_CONTENTS}/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APPNAME}" ${APP_CONTENTS}/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier me.pierluigi.${APPNAME}" ${APP_CONTENTS}/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundlePackageType APPL" ${APP_CONTENTS}/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APPNAME}" ${APP_CONTENTS}/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" ${APP_CONTENTS}/Info.plist
	/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 10.15" ${APP_CONTENTS}/Info.plist
	cp ${RELEASE_DIRECTORY}/${CFBUNDLEEXECUTABLE} ${APP_CONTENTS}/MacOS/
	cp ${BUILD_DIRECTORY}/Icon.icns ${APP_CONTENTS}/Resources/
	mkdir -p "${APP_CONTENTS}/Library/LoginItems"
	unzip "${RELEASE_DIRECTORY}/LaunchAtLogin_LaunchAtLogin.bundle/Contents/Resources/LaunchAtLoginHelper-with-runtime.zip" -d "${APP_CONTENTS}/Library/LoginItems"
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier me.pierluigi.${APPNAME}-LaunchAtLoginHelper" "${APP_CONTENTS}/Library/LoginItems/LaunchAtLoginHelper.app/Contents/Info.plist"

codesign:
	codesign --force --deep --sign - -o runtime --entitlements ${SUPPORTFILES}/${APPNAME}.entitlements ${APP_DIRECTORY}

clean:
	rm -rf .build
	rm -rf ${APP_CONTENTS}

.PHONY: build icon bundle clean

APPNAME=NextEvt
SUPPORTFILES=./${APPNAME}/
BUILD_DIRECTORY = ./.build/apple/Products/Release
APP_DIRECTORY=./.build/${APPNAME}.app
APP_CONTENTS="${APP_DIRECTORY}/Contents"
CFBUNDLEEXECUTABLE=${APPNAME}
VERSION=`git tag | sort -V | tail -1 | cut -c2-`

install: build bundle codesign

build: 
	swift build -c release --arch arm64 --arch x86_64

bundle:
	rm -rf ${APP_CONTENTS}
	mkdir -p "${APP_CONTENTS}/MacOS/"
	cp ${SUPPORTFILES}/Info.plist ${APP_CONTENTS}
	/usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion en-IT" ${APP_CONTENTS}/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APPNAME}" ${APP_CONTENTS}/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier me.pierluigi.${APPNAME}" ${APP_CONTENTS}/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundlePackageType APPL" ${APP_CONTENTS}/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APPNAME}" ${APP_CONTENTS}/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" ${APP_CONTENTS}/Info.plist
	/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 10.15" ${APP_CONTENTS}/Info.plist
	cp ${BUILD_DIRECTORY}/${CFBUNDLEEXECUTABLE} ${APP_CONTENTS}/MacOS/
	mkdir -p "${APP_CONTENTS}/Library/LoginItems"
	unzip "${BUILD_DIRECTORY}/LaunchAtLogin_LaunchAtLogin.bundle/Contents/Resources/LaunchAtLoginHelper-with-runtime.zip" -d "${APP_CONTENTS}/Library/LoginItems"
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier me.pierluigi.${APPNAME}-LaunchAtLoginHelper" "${APP_CONTENTS}/Library/LoginItems/LaunchAtLoginHelper.app/Contents/Info.plist"

codesign:
	codesign --force --deep --sign - -o runtime --entitlements ${SUPPORTFILES}/${APPNAME}.entitlements ${APP_DIRECTORY}

clean:
	rm -rf .build
	rm -rf ${APP_CONTENTS}

.PHONY: build bundle clean

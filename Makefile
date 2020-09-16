APPNAME=NextEvt
SUPPORTFILES=./${APPNAME}/
PLATFORM=x86_64-apple-macosx
BUILD_DIRECTORY = ./.build/${PLATFORM}/release
APP_DIRECTORY=./.build/${APPNAME}.app
CFBUNDLEEXECUTABLE=${APPNAME}

install: build bundle codesign

build: 
	swift build -c release

bundle:
	mkdir -p ${APP_DIRECTORY}/Contents/MacOS/
	cp ${SUPPORTFILES}/Info.plist ${APP_DIRECTORY}/Contents
	/usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion en-IT" ${APP_DIRECTORY}/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APPNAME}" ${APP_DIRECTORY}/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier me.pierluigi.${APPNAME}" ${APP_DIRECTORY}/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundlePackageType APPL" ${APP_DIRECTORY}/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APPNAME}" ${APP_DIRECTORY}/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 10.15" ${APP_DIRECTORY}/Contents/Info.plist
	cp ${BUILD_DIRECTORY}/${CFBUNDLEEXECUTABLE} ${APP_DIRECTORY}/Contents/MacOS/

codesign:
	codesign --force --deep --sign - -o runtime --entitlements ${SUPPORTFILES}/${APPNAME}.entitlements ${APP_DIRECTORY}

clean:
	rm -rf .build

.PHONY: build bundle clean

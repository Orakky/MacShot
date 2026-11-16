# MacShot — 本地构建与门禁（ADR-001 / ADR-015：无第三方工具）
XCODEPROJ := MacShot.xcodeproj
SCHEME    := MacShot
DERIVED   := build/Derived
PRODUCT   := $(DERIVED)/Build/Products/Debug/MacShot.app
VERSION   := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Config/Info.plist 2>/dev/null)

.PHONY: doctor build release test run run-term dmg install check clean sign probe probe-permission

doctor:
	@sh scripts/doctor.sh

build:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug \
	  -derivedDataPath $(DERIVED) -quiet build
	@echo "→ $(PRODUCT)"

release:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Release \
	  -derivedDataPath $(DERIVED) -quiet build

test:
	@cd Packages/MacShotKit && swift test 2>&1 | tail -3

run: build
	@pkill -x MacShot 2>/dev/null || true
	@open "$(PRODUCT)" && echo "→ 已启动；状态栏应出现 ✂，按 F1 截图"

# Q-18=B：ad-hoc 签名的 .app 每次重编都换 cdhash ⇒ TCC 授权每次失效（P-002/E-039）。
# 直接 exec 产物时，采集归属终端已授予的屏幕录制权限，开发循环不受影响；代价是
# 这条路证明不了 .app 自身身份可用（V-021 因此仍闭不了，见 E-033）。
run-term: build
	@pkill -x MacShot 2>/dev/null || true
	@"$(PRODUCT)/Contents/MacOS/MacShot"

probe: build
	@"$(PRODUCT)/Contents/MacOS/MacShot" --probe-capture

probe-permission: build
	@"$(PRODUCT)/Contents/MacOS/MacShot" --probe-permission

sign: build
	codesign --force --sign - --timestamp=none "$(PRODUCT)"
	codesign -dv "$(PRODUCT)" 2>&1 | grep -E 'Signature|Identifier' || true

dmg: release
	@mkdir -p build
	@rm -f build/MacShot-$(VERSION).dmg
	hdiutil create -volname MacShot -srcfolder "$(DERIVED)/Build/Products/Release/MacShot.app" \
	  -ov -format UDZO build/MacShot-$(VERSION).dmg
	@echo "→ build/MacShot-$(VERSION).dmg"

install: build
	@rm -rf "$(HOME)/Applications/MacShot.app"
	@mkdir -p "$(HOME)/Applications"
	cp -R "$(PRODUCT)" "$(HOME)/Applications/"
	xattr -dr com.apple.quarantine "$(HOME)/Applications/MacShot.app" 2>/dev/null || true
	@echo "→ 已安装到 ~/Applications/MacShot.app"

check: doctor
	@sh scripts/check-style.sh
	@sh scripts/check-deps.sh
	@python3 scripts/check-docs.py
	@$(MAKE) --no-print-directory test
	@$(MAKE) --no-print-directory build
	@echo "✔ check 通过"

clean:
	rm -rf build Packages/MacShotKit/.build
	@echo "cleaned"

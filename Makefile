# MacShot — 本地构建与门禁（ADR-001 / ADR-015：无第三方工具）
XCODEPROJ := MacShot.xcodeproj
SCHEME    := MacShot
DERIVED   := build/Derived
PRODUCT   := $(DERIVED)/Build/Products/Debug/MacShot.app
RELEASE   := $(DERIVED)/Build/Products/Release/MacShot.app
ICNS      := build/macshot.icns
VERSION   := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Config/Info.plist 2>/dev/null)

.PHONY: doctor build release test run run-term dmg install check clean sign probe probe-permission probe-menu probe-chrome probe-freeze icon appicon

doctor:
	@sh scripts/doctor.sh

build:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug \
	  -derivedDataPath $(DERIVED) -quiet build
	@echo "→ $(PRODUCT)"

release:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Release \
	  -derivedDataPath $(DERIVED) -quiet build

# 图标真源 = assets/branding/macshot-icon.svg；build/macshot.icns 是产物，不入库
icon:
	@sh scripts/make-icon.sh

# 往 .app 里加资源会让原 ad-hoc 签名失效 ⇒ 注入后重签（D-02）。
# appicon = "把产物做成能用的一份"，所以 run/run-term/probe 都挂在它上面，不让开发入口跑在缺素材的 bundle 上。
appicon: build icon
	@sh scripts/inject-brand.sh "$(PRODUCT)"

test:
	@cd Packages/MacShotKit && swift test 2>&1 | tail -3

run: appicon
	@pkill -x MacShot 2>/dev/null || true
	@open "$(PRODUCT)" && echo "→ 已启动；状态栏应出现品牌图形，按 F1 截图"

# Q-18=B：ad-hoc 签名的 .app 每次重编都换 cdhash ⇒ TCC 授权每次失效（P-002/E-039）。
# 直接 exec 产物时，采集归属终端已授予的屏幕录制权限，开发循环不受影响；代价是
# 这条路证明不了 .app 自身身份可用（V-021 因此仍闭不了，见 E-033）。
run-term: appicon
	@pkill -x MacShot 2>/dev/null || true
	@"$(PRODUCT)/Contents/MacOS/MacShot"

probe: appicon
	@"$(PRODUCT)/Contents/MacOS/MacShot" --probe-capture

probe-permission: appicon
	@"$(PRODUCT)/Contents/MacOS/MacShot" --probe-permission
probe-menu: appicon
	@"$(PRODUCT)/Contents/MacOS/MacShot" --probe-menu
probe-chrome: appicon
	@"$(PRODUCT)/Contents/MacOS/MacShot" --dump-chrome build/chrome.png
	@echo "→ build/chrome.png（遮罩界面自绘，用来看，不是用来判绿）"

# 冻结语义 + 剪贴板哨兵的运行时取证：会在你屏幕上开约 4 秒遮罩
probe-freeze: appicon
	@sh scripts/probe-freeze.sh

sign: build
	codesign --force --sign - --timestamp=none "$(PRODUCT)"
	codesign -dv "$(PRODUCT)" 2>&1 | grep -E 'Signature|Identifier' || true

dmg: release icon
	@mkdir -p build
	@rm -f build/MacShot-$(VERSION).dmg
	@sh scripts/inject-brand.sh "$(RELEASE)"
	hdiutil create -volname MacShot -srcfolder "$(RELEASE)" \
	  -ov -format UDZO build/MacShot-$(VERSION).dmg
	@echo "→ build/MacShot-$(VERSION).dmg"

install: appicon
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
	@$(MAKE) --no-print-directory appicon
	@echo "✔ check 通过"

clean:
	rm -rf build Packages/MacShotKit/.build
	@echo "cleaned"

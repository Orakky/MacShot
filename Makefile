# MacShot — 本地构建与门禁（ADR-001 / ADR-015：无第三方工具）
XCODEPROJ := MacShot.xcodeproj
SCHEME    := MacShot
DERIVED   := build/Derived
PRODUCT   := $(DERIVED)/Build/Products/Debug/MacShot.app
RELEASE   := $(DERIVED)/Build/Products/Release/MacShot.app
ICNS      := build/macshot.icns
VERSION   := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Config/Info.plist 2>/dev/null)

# Q-18=A（11-17 落地）：登录钥匙串里有自签身份 "MacShot Dev" 就用它签名 ⇒ designated requirement
# 变成 `identifier + certificate leaf`，重建不再换身份、屏幕录制授权不再每次失效；
# 没有身份时自动退回 ad-hoc（`-`），构建与门禁不会因为环境缺身份而变红。
SIGN_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q "MacShot Dev" && echo "MacShot Dev" || echo "-")

.PHONY: doctor build release test run run-term dmg install check clean sign probe probe-permission probe-menu probe-chrome probe-clipboard probe-pin probe-hotkey probe-freeze icon appicon

doctor:
	@echo "  签名身份 = $(SIGN_IDENTITY)（有 MacShot Dev 则 DR=identifier+leaf，重建不掉授权）"
	@echo "  当前产物 DR = $$(codesign -d -r- "$(PRODUCT)" 2>&1 | grep -oE "(identifier|cdhash).*" | head -1)"
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
	@MACSHOT_SIGN_IDENTITY="$(SIGN_IDENTITY)" sh scripts/inject-brand.sh "$(PRODUCT)"

test:
	@cd Packages/MacShotKit && swift test > $(CURDIR)/build/test.log 2>&1; rc=$$?; 	  tail -4 $(CURDIR)/build/test.log; 	  grep -q "Test run with" $(CURDIR)/build/test.log 	    || { echo "✗ 没跑到测试（编译失败或空套件），不算绿"; exit 1; }; 	  exit $$rc

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

# NFR-005 / NFR-008 的内存读数：开 N 张贴图（默认 10 张 4K 源）→ 关全部 → 回基线
# 夹具是随机噪声（纯色会被内存压缩器吃掉，量的是压缩器不是贴图）；会短暂在你屏幕上开 N 个窗
probe-memory: appicon
	@rm -f /tmp/macshot-probe-memory.txt
	@pkill -x MacShot 2>/dev/null; sleep 1; \
	open -n "$(PRODUCT)" --args --probe-memory 10 1920 1080 9000; \
	sleep 16; PID=$$(pgrep -x MacShot | head -1); \
	echo "   外部裁判 pid=$$PID：ps 报 rss=$$(( $$(ps -o rss= -p $$PID) / 1024 ))MB"; \
	sleep 8; echo "→ 探针读数："; cat /tmp/macshot-probe-memory.txt 2>/dev/null | sed 's/^/   /'

# V-037④ 的机制半：改绑 → 退出 → 再启动读回 → 还原，三次独立启动都算一次取证
probe-hotkey: appicon
	@rm -f /tmp/macshot-probe-hotkey.txt
	@for m in set show restore; do \
	  pkill -x MacShot 2>/dev/null; sleep 0.6; \
	  open -n "$(PRODUCT)" --args --probe-hotkey "$$m"; sleep 2.5; \
	done; \
	echo "→ 三次独立启动的读数："; cat /tmp/macshot-probe-hotkey.txt 2>/dev/null | sed 's/^/   /'

# Q-04"只写 PNG"的真壳判据：合成图写进系统剪贴板，再读回 types + DPI + TIFF 来源对照
# 注意：这条路会覆盖你剪贴板里的东西（探针本来就要测"写"这个动作）
probe-clipboard: appicon
	@rm -f /tmp/macshot-probe-clipboard.txt
	@pkill -x MacShot 2>/dev/null; sleep 1; \
	open -n "$(PRODUCT)" --args --probe-clipboard; sleep 5; \
	echo "→ 剪贴板读数："; cat /tmp/macshot-probe-clipboard.txt 2>/dev/null | sed 's/^/   /'

# B-028 撑高形态的"眼睛"通道：真贴窗 + 编辑态，把视图离屏渲染成 build/probe-pin.png
# 采集被 TCC 拒（cdhash 换了）时探针自动退回合成画面——这里裁的是工具带形态，不是屏幕内容
probe-pin: appicon
	@rm -f /tmp/macshot-probe-pin.txt /tmp/macshot-probe-pin.png
	@open -n "$(PRODUCT)" --args --probe-pin 2500
	@sleep 6; cp /tmp/macshot-probe-pin.png build/probe-pin.png 2>/dev/null; \
	 echo "→ build/probe-pin.png + 读数："; cat /tmp/macshot-probe-pin.txt 2>/dev/null | sed 's/^/   /'

# 冻结语义 + 剪贴板哨兵的运行时取证：会在你屏幕上开约 4 秒遮罩
probe-freeze: appicon
	@sh scripts/probe-freeze.sh

sign: build
	codesign --force --sign "$(SIGN_IDENTITY)" --timestamp=none "$(PRODUCT)"
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

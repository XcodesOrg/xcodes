SHELL = /bin/bash

prefix ?= /usr/local
bindir ?= $(prefix)/bin
srcdir = Sources

REPODIR = $(shell pwd)
BUILDDIR = $(REPODIR)/.build
SOURCES = $(wildcard $(srcdir)/**/*.swift)
RELEASEBUILDDIR = $(shell dir=$$($(SWIFT_RELEASE_BUILD) --show-bin-path) && printf '%s/xcodes' "$$dir")
SWIFT_BUILD_FLAGS ?=
.DEFAULT_GOAL = all

.PHONY: all
all: xcodes

# -Onone is a temporary workaround for FB7347879
# "swift build" gets stuck on a certain file in this project when using release configuration
# https://github.com/apple/swift/pull/26660
SWIFT_RELEASE_BUILD = swift build \
		--configuration release \
		-Xswiftc -Onone \
		--disable-sandbox \
		--build-path "$(BUILDDIR)" \
		--arch arm64 \
		--arch x86_64 $(SWIFT_BUILD_FLAGS)

.PHONY: xcodes
xcodes: $(SOURCES)
	@$(SWIFT_RELEASE_BUILD)

.PHONY: release-bin-path
release-bin-path:
	@path="$(RELEASEBUILDDIR)"; test -n "$$path" && printf '%s\n' "$$path"

.PHONY: sign
sign: xcodes
	@codesign \
		--sign "Developer ID Application: Matt Kiazyk (ZU6GR6B2FY)" \
		--prefix com.xcodesorg. \
		--options runtime \
		--timestamp \
		"$(RELEASEBUILDDIR)"

.PHONY: zip
zip: sign
	@rm xcodes.zip 2> /dev/null || true
	@zip --junk-paths xcodes.zip "$(RELEASEBUILDDIR)"
	@open -R xcodes.zip

# E.g.
# make notarize TEAMID="ABCD123"
.PHONY: notarize
notarize: zip
	./notarize.sh xcodes.zip "$(TEAMID)"

# E.g.
# make bottle VERSION=0.4.0
.PHONY: bottle
bottle: sign
	@rm -r xcodes 2> /dev/null || true
	@rm *.tar.gz 2> /dev/null || true
	@mkdir -p xcodes/$(VERSION)/bin
	@cp "$(RELEASEBUILDDIR)" xcodes/$(VERSION)/bin
	@tar -zcvf xcodes-$(VERSION).mojave.bottle.tar.gz -C "$(REPODIR)" xcodes
	shasum -a 256 xcodes-$(VERSION).mojave.bottle.tar.gz | cut -f1 -d' '
	@open -R xcodes-$(VERSION).mojave.bottle.tar.gz

.PHONY: install
install: xcodes
	@install -d "$(bindir)"
	@install "$(RELEASEBUILDDIR)" "$(bindir)"

.PHONY: uninstall
uninstall:
	@rm -rf "$(bindir)/xcodes"

.PHONY: distclean
distclean:
	@path="$(RELEASEBUILDDIR)"; if [ -n "$$path" ]; then rm -f "$$path"; fi

.PHONY: clean
clean: distclean
	@rm -rf "$(BUILDDIR)"

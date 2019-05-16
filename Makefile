SHELL = /bin/bash

prefix ?= /usr/local
bindir ?= $(prefix)/bin
srcdir = Sources

REPODIR = $(shell pwd)
BUILDDIR = $(REPODIR)/.build
SOURCES = $(wildcard $(srcdir)/**/*.swift)

.DEFAULT_GOAL = all

.PHONY: all
all: xcodes

.PHONY: xcodes
xcodes: $(SOURCES)
	@swift build \
		-c release \
		--disable-sandbox \
		--build-path "$(BUILDDIR)" \
		--static-swift-stdlib \
		-Xswiftc "-target" \
		-Xswiftc "x86_64-apple-macosx10.13"

.PHONY: sign
sign: xcodes
	@codesign \
		-s "Developer ID Application: Robots and Pencils Inc. (PBH8V487HB)" \
		--prefix com.robotsandpencils. \
		"$(BUILDDIR)/release/xcodes"

.PHONY: zip
zip: sign
	@rm xcodes.zip 2> /dev/null || true
	@zip -j xcodes.zip "$(BUILDDIR)/release/xcodes"
	@open -R xcodes.zip

.PHONY: install
install: xcodes
	@install -d "$(bindir)"
	@install "$(BUILDDIR)/release/xcodes" "$(bindir)"

.PHONY: uninstall
uninstall:
	@rm -rf "$(bindir)/xcodes"

.PHONY: project
project:
	@swift package generate-xcodeproj \
		--xcconfig-overrides Package.xcconfig

.PHONY: distclean
distclean:
	@rm -f $(BUILDDIR)/release

.PHONY: clean
clean: distclean
	@rm -rf $(BUILDDIR)

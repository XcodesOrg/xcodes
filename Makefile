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
		-s "Developer ID Application: Brandon Evans (Z2R9WCWER2)" \
		--prefix ca.brandonevans. \
		"$(BUILDDIR)/release/xcodes"

.PHONY: zip
zip: sign
	@zip -j xcodes.zip "$(BUILDDIR)/release/xcodes"
	@open -R xcodes.zip

.PHONY: install
install: xcodes
	@install -d "$(bindir)"
	@install "$(BUILDDIR)/release/xcodes" "$(bindir)"

.PHONY: uninstall
uninstall:
	@rm -rf "$(bindir)/xcodes"

.PHONY: clean
distclean:
	@rm -f $(BUILDDIR)/release

.PHONY: clean
clean: distclean
	@rm -rf $(BUILDDIR)


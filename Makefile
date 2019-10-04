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

# -Onone is a temporary workaround for FB7347879
# "swift build" gets stuck on a certain file in this project when using release configuration
# https://github.com/apple/swift/pull/26660
.PHONY: xcodes
xcodes: $(SOURCES)
	@swift build \
		--configuration release \
		-Xswiftc -Onone \
		--disable-sandbox \
		--build-path "$(BUILDDIR)" \

.PHONY: sign
sign: xcodes
	@codesign \
		--sign "Developer ID Application: Robots and Pencils Inc. (PBH8V487HB)" \
		--prefix com.robotsandpencils. \
		--options runtime \
		--timestamp \
		"$(BUILDDIR)/release/xcodes"

.PHONY: zip
zip: sign
	@rm xcodes.zip 2> /dev/null || true
	@zip --junk-paths xcodes.zip "$(BUILDDIR)/release/xcodes"
	@open -R xcodes.zip

# E.g.
# make notarize USERNAME="test@example.com" PASSWORD="@keychain:altool" ASC_PROVIDER=MyOrg
.PHONY: notarize
notarize: zip
	./notarize.sh "$(USERNAME)" "$(PASSWORD)" "$(ASC_PROVIDER)" xcodes.zip

# E.g.
# make bottle VERSION=0.4.0
.PHONY: bottle
bottle: sign
	@rm -r xcodes 2> /dev/null || true
	@rm *.tar.gz 2> /dev/null || true
	@mkdir -p xcodes/$(VERSION)/bin
	@cp "$(BUILDDIR)/release/xcodes" xcodes/$(VERSION)/bin
	@tar -zcvf xcodes-$(VERSION).mojave.bottle.tar.gz -C "$(REPODIR)" xcodes
	shasum -a 256 xcodes-$(VERSION).mojave.bottle.tar.gz | cut -f1 -d' '
	@open -R xcodes-$(VERSION).mojave.bottle.tar.gz

.PHONY: install
install: xcodes
	@install -d "$(bindir)"
	@install "$(BUILDDIR)/release/xcodes" "$(bindir)"

.PHONY: uninstall
uninstall:
	@rm -rf "$(bindir)/xcodes"

.PHONY: distclean
distclean:
	@rm -f $(BUILDDIR)/release

.PHONY: clean
clean: distclean
	@rm -rf $(BUILDDIR)

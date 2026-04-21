NAME    := apfel-home-assistant
VERSION := $(or $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//'),0.0.0)
DIST    := dist
TARBALL := $(DIST)/$(NAME)-$(VERSION).tar.gz

.DEFAULT_GOAL := help
.PHONY: help tarball sha256 test clean

help:
	@echo "Targets:"
	@echo "  help     Show this message (default)."
	@echo "  test     Run test/smoke.sh against the working tree."
	@echo "  tarball  Build $(TARBALL) from HEAD."
	@echo "  sha256   Print the sha256 of the tarball (builds it first)."
	@echo "  clean    Remove $(DIST)/."

tarball:
	@mkdir -p $(DIST)
	git archive --format=tar.gz --prefix=$(NAME)-$(VERSION)/ -o $(TARBALL) HEAD
	@echo "built $(TARBALL)"

sha256: tarball
	@shasum -a 256 $(TARBALL)

test:
	./test/smoke.sh

clean:
	rm -rf $(DIST)

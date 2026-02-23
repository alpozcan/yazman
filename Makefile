PREFIX ?= /usr/local

.PHONY: build release install uninstall clean test lint run

build:
	swift build

release:
	swift build -c release

install: build
	cp .build/debug/muharrir $(PREFIX)/bin/muharrir

install-release: release
	cp .build/release/muharrir $(PREFIX)/bin/muharrir

uninstall:
	rm -f $(PREFIX)/bin/muharrir

clean:
	swift package clean

test:
	swift test

lint:
	swiftlint lint --strict

run:
	swift run muharrir

log:
	log stream --predicate 'subsystem == "dev.muharrir.cli"' --level debug

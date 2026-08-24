.PHONY: help deps build overlay config install restart sync uninstall test

help:
	@echo "make deps      install Fedora build and runtime packages"
	@echo "make build     build Tide Island with the patches and install it"
	@echo "make overlay   create or refresh the Caelestia config fork"
	@echo "make config    apply the two settings that live in user config files"
	@echo "make install   deps + build + overlay + restart"
	@echo "make restart   restart the Caelestia shell"
	@echo "make sync      move to the latest upstream Tide Island revision"
	@echo "make test      run Tide Island's test suite, theme bridge included"
	@echo "make uninstall remove the island and drop back to stock Caelestia"

deps:
	@scripts/install-deps.sh

build:
	@scripts/build-tide.sh

overlay:
	@scripts/apply-overlay.sh

config:
	@scripts/apply-config.sh

restart:
	@scripts/restart-shell.sh

install: deps build overlay config restart

sync:
	@scripts/sync-upstream.sh

test:
	@ctest --test-dir .build/Tide-island/build --output-on-failure

uninstall:
	@scripts/uninstall.sh

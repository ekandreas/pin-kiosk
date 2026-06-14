# Flipperklubben Kiosk – bekvämlighetskommandon
.PHONY: help test lint build build-pi3 build-pi4 build-pi5 run-dev clean

help:
	@echo "Mål:"
	@echo "  make test       Kör enhetstester"
	@echo "  make lint       py_compile + shellcheck (om installerat)"
	@echo "  make run-dev    Kör agenten lokalt utan webbläsare (--no-browser --once -v)"
	@echo "  make build      Bygg alla images (pi3, pi4, pi5) – kräver Debian/Docker"
	@echo "  make build-pi4  Bygg endast pi4"
	@echo "  make clean      Ta bort byggartefakter och dist/"

test:
	python3 -m unittest discover -s tests -v

lint:
	python3 -m py_compile kiosk/agent/kiosk_agent.py tests/test_agent.py
	@command -v shellcheck >/dev/null 2>&1 && \
		shellcheck kiosk/bin/kiosk-session.sh build/build.sh \
		build/stage-kiosk/*/*.sh build/stage-kiosk/prerun.sh || \
		echo "shellcheck ej installerat – hoppar över skalkontroll"

run-dev:
	python3 kiosk/agent/kiosk_agent.py --no-browser --once -v

build:
	./build/build.sh

build-pi3:
	./build/build.sh pi3

build-pi4:
	./build/build.sh pi4

build-pi5:
	./build/build.sh pi5

clean:
	rm -rf build/pi-gen dist \
		build/stage-kiosk/01-install/files/payload \
		build/stage-kiosk/02-config/files
	find . -name '__pycache__' -type d -prune -exec rm -rf {} +

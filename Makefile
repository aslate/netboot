SHELL := /bin/bash

.DEFAULT_GOAL := help
.NOTPARALLEL:
.PHONY: help preflight packages bootstrap links firewall firewall-enable \
	firewall-remove services render validate setup setup-with-firewall start stop \
	restart reload status logs tui check

help: ## Show the available project commands
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

preflight: ## Check the host, address, configuration, and payload links
	./scripts/setup/00-preflight.sh

packages: ## Install required host and image-preparation packages
	./scripts/setup/10-install-packages.sh

bootstrap: ## Install the packaged UEFI iPXE bootstrap into tftp/
	./scripts/setup/20-install-ipxe-bootstrap.sh

links: ## Recreate the HTTP compatibility symlinks
	./scripts/setup/25-recreate-http-symlinks.sh

firewall: ## Add netboot rules to an already-running firewalld
	./scripts/setup/30-configure-firewalld.sh

firewall-enable: ## Enable firewalld and add netboot rules (use locally)
	./scripts/setup/30-configure-firewalld.sh --enable

firewall-remove: ## Remove the project netboot firewall rules
	./scripts/setup/30-configure-firewalld.sh --remove

render: ## Render repository-local service configuration
	./scripts/netbootctl render

services: ## Render and start standalone Caddy and dnsmasq
	./scripts/netbootctl start

validate: ## Validate rendered configuration, processes, listeners, and HTTP/PXE state
	./scripts/setup/90-validate-host.sh

setup: ## Install this host without enabling or changing its firewall
	$(MAKE) packages
	$(MAKE) bootstrap
	$(MAKE) links
	$(MAKE) services
	$(MAKE) validate

setup-with-firewall: ## Full setup, explicitly enabling firewalld (use locally)
	$(MAKE) packages
	$(MAKE) bootstrap
	$(MAKE) links
	$(MAKE) firewall-enable
	$(MAKE) services
	$(MAKE) validate

start: ## Start Caddy and dnsmasq
	./scripts/netbootctl start

stop: ## Stop dnsmasq and Caddy
	./scripts/netbootctl stop

restart: ## Restart standalone Caddy and dnsmasq
	./scripts/netbootctl restart

reload: ## Render, validate, and activate service configuration
	./scripts/netbootctl reload

status: ## Show verified standalone daemon state
	./scripts/netbootctl status

logs: ## Show and follow repository-local Caddy and dnsmasq logs
	./scripts/netbootctl logs

tui: ## Open the passive netboot visibility TUI
	./scripts/netbootctl tui

check: ## Run developer shell, formatting, migration, and regression checks
	shellcheck $$(rg --files -g '*.sh' scripts packages | grep -v '^archive/' | sort)
	shfmt -d scripts/netbootctl scripts/apply-netboot-config.sh scripts/setup/00-preflight.sh scripts/setup/40-install-enable-services.sh scripts/setup/90-validate-host.sh
	python3 -m unittest discover -s tests -p 'test_*.py'
	python3 -m unittest test_netbootctl.py test_almalinux_boot.py
	@if [[ -d tests/bats ]]; then bats tests/bats; fi
	@if rg -n '(/etc/(dnsmasq|caddy)|systemctl (start|stop|reload|restart|is-active)|journalctl)' scripts/netbootctl scripts/enable-caddy-access-log.sh scripts/setup/40-install-enable-services.sh scripts/setup/90-validate-host.sh; then \
		echo 'standalone migration assertion failed' >&2; exit 1; fi

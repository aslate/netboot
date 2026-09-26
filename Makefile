SHELL := /bin/bash

.DEFAULT_GOAL := help
.NOTPARALLEL:
.PHONY: help preflight packages bootstrap links firewall firewall-enable \
	firewall-remove services validate setup setup-with-firewall start stop \
	reload logs tui

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

services: ## Install configuration and enable/start Caddy and dnsmasq
	./scripts/setup/40-install-enable-services.sh

validate: ## Validate installed configuration, services, and local HTTP
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

reload: ## Reinstall, validate, and activate service configuration
	./scripts/netbootctl reload

logs: ## Show and follow Caddy and dnsmasq logs
	./scripts/netbootctl logs

tui: ## Open the passive netboot visibility TUI
	./scripts/netbootctl tui

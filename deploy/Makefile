# Velorki self-hosting helpers. Thin wrappers around deploy/bin/*.
#
#   make up          start caddy + brouter + brouter-updater
#   make up-api      ...also start the API container (--profile api)
#   make sync-now    fetch segment updates now instead of waiting
#   make logs        follow all logs        (make logs S=brouter)
#   make route-test  request a real route through Caddy

SHELL := /bin/bash
COMPOSE := docker compose
S ?=

.PHONY: help up up-api down restart ps build sync-now logs route-test health update-brouter

help:
	@sed -n 's/^#   //p' Makefile

up:
	$(COMPOSE) up -d

up-api:
	$(COMPOSE) --profile api up -d

down:
	$(COMPOSE) --profile api down

restart:
	$(COMPOSE) --profile api restart

ps:
	$(COMPOSE) --profile api ps

build:
	$(COMPOSE) build

sync-now:
	@./bin/sync-now

logs:
	@./bin/logs $(S)

route-test:
	@./bin/route-test

health:
	@$(COMPOSE) ps --format 'table {{.Service}}\t{{.Status}}'

# Rebuild BRouter after bumping BROUTER_VERSION in .env.
update-brouter:
	$(COMPOSE) build --no-cache brouter
	$(COMPOSE) up -d brouter

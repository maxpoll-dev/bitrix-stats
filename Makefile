SHELL := /bin/bash
DOCKER  := docker compose -f docker-compose.yml

.PHONY: up down rebuild logs shell

# ===== CORE ======

# Поднять докер
up:
	$(DOCKER) up -d

# Выключаем контейнеры и сносим данные
down:
	$(DOCKER) down -v

# Ребилд докера
rebuild:
	$(DOCKER) down -v
	$(DOCKER) build --no-cache
	$(DOCKER) up -d

# ===== ADVANCED ======

# Логи
logs: N ?= postgres
logs:
	$(DOCKER) logs

# Зайти в контейнер
shell: N ?= postgres
shell:
	$(DOCKER) exec $(N) sh

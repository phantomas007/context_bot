PHP     = docker compose exec -w /var/www/html/app php php
BIN     = docker compose exec -w /var/www/html/app php ./vendor/bin
COMPOSE = docker compose

# Окружение: local (по умолчанию) | prod
ENV ?= local

# Маппинг на Symfony-окружения
SYMFONY_ENV = $(if $(filter prod,$(ENV)),prod,dev)
APP_DEBUG   = $(if $(filter prod,$(ENV)),0,1)

# docker exec с нужным окружением
PHP_ENV = docker compose exec -w /var/www/html/app \
            -e APP_ENV=$(SYMFONY_ENV) -e APP_DEBUG=$(APP_DEBUG) \
            php php

GREEN  = \033[0;32m
YELLOW = \033[0;33m
CYAN   = \033[0;36m
RED    = \033[0;31m
BOLD   = \033[1m
RESET  = \033[0m

.PHONY: help run stop restart db-reset \
        composer-install console migrate fixtures cache-clear \
        cs-check cs-fix phpstan lint test \
        _wait-db

# ─── Help ─────────────────────────────────────────────────────────────────────

help: ## Показать список команд
	@echo ""
	@echo "  $(BOLD)Доступные команды:$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-15s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "  Примеры:"
	@echo "  $(CYAN)make run$(RESET)              # ENV=local (по умолчанию)"
	@echo "  $(CYAN)make run ENV=prod$(RESET)     # prod (без фикстур, cache warmup)"
	@echo ""

# ─── Main ─────────────────────────────────────────────────────────────────────

run: ## Запустить проект: make run [ENV=local|prod]
	@echo ""
	@echo "$(BOLD)$(GREEN)══════════════════════════════════════════$(RESET)"
	@echo "$(BOLD)$(GREEN)  ЗАПУСК ПРОЕКТА  [ENV=$(ENV) → APP_ENV=$(SYMFONY_ENV)]$(RESET)"
	@echo "$(BOLD)$(GREEN)══════════════════════════════════════════$(RESET)"
	@echo ""

	@if [ ! -f app/.env.local ]; then \
		if [ -f app/.env.local.example ]; then \
			cp app/.env.local.example app/.env.local; \
			echo "$(GREEN)  ✔ Создан app/.env.local из app/.env.local.example$(RESET)"; \
		else \
			echo "$(RED)  ✗ Файл app/.env.local не найден и нет шаблона!$(RESET)"; exit 1; \
		fi; \
	fi

	@echo "$(CYAN)▶ [1/5] Сборка образов (только изменённые)...$(RESET)"
	@APP_ENV=$(SYMFONY_ENV) APP_DEBUG=$(APP_DEBUG) $(COMPOSE) build
	@echo "$(GREEN)  ✔ Образы актуальны$(RESET)"
	@echo ""

	@echo "$(CYAN)▶ [2/5] Запуск контейнеров [APP_ENV=$(SYMFONY_ENV), APP_DEBUG=$(APP_DEBUG)]...$(RESET)"
	@APP_ENV=$(SYMFONY_ENV) APP_DEBUG=$(APP_DEBUG) $(COMPOSE) up -d
	@echo "$(GREEN)  ✔ Контейнеры запущены$(RESET)"
	@echo ""

	@echo "$(CYAN)▶ [3/5] Ожидание готовности базы данных...$(RESET)"
	@$(MAKE) _wait-db
	@echo ""

	@echo "$(CYAN)▶ [4/5] Применение миграций...$(RESET)"
	@$(PHP_ENV) bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration
	@echo "$(GREEN)  ✔ Миграции актуальны$(RESET)"
	@echo ""

	@if [ "$(ENV)" != "prod" ]; then \
		echo "$(CYAN)▶ [5/5] Загрузка фикстур...$(RESET)"; \
		$(PHP_ENV) bin/console doctrine:fixtures:load --no-interaction; \
		echo "$(GREEN)  ✔ Фикстуры загружены$(RESET)"; \
	else \
		echo "$(CYAN)▶ [5/5] Прогрев кеша (prod)...$(RESET)"; \
		$(PHP_ENV) bin/console cache:warmup; \
		echo "$(GREEN)  ✔ Кеш прогрет$(RESET)"; \
	fi
	@echo ""

	@if [ "$(ENV)" != "prod" ]; then \
		echo "$(CYAN)▶ [lint] Проверка кода...$(RESET)"; \
		echo ""; \
		$(MAKE) lint; \
		echo ""; \
	else \
		echo "$(YELLOW)  i Линтеры пропущены в prod (dev-зависимости не установлены)$(RESET)"; \
		echo ""; \
	fi

	@echo "$(BOLD)$(GREEN)══════════════════════════════════════════$(RESET)"
	@echo "$(BOLD)$(GREEN)  ✔ ГОТОВО [$(ENV)]  →  http://localhost$(RESET)"
	@echo "$(BOLD)$(GREEN)══════════════════════════════════════════$(RESET)"
	@echo ""

db-reset: ## Удалить том БД — пересоздать при следующем make run (если сменили пароли в .env)
	@echo "$(CYAN)▶ Останавливаю контейнеры и удаляю том БД...$(RESET)"
	@$(COMPOSE) down -v
	@echo "$(GREEN)  ✔ Том удалён — запустите make run для пересоздания БД$(RESET)"

stop: ## Остановить все контейнеры
	@echo "$(CYAN)▶ Остановка контейнеров...$(RESET)"
	@$(COMPOSE) stop
	@echo "$(GREEN)  ✔ Контейнеры остановлены$(RESET)"

restart: ## Перезапустить PHP-контейнер
	@echo "$(CYAN)▶ Перезапуск PHP...$(RESET)"
	@$(COMPOSE) restart php
	@echo "$(GREEN)  ✔ Готово$(RESET)"

# ─── Symfony ──────────────────────────────────────────────────────────────────

composer-install: ## Установить зависимости Composer: make composer-install [ENV=prod]
	@echo "$(CYAN)▶ composer install [APP_ENV=$(SYMFONY_ENV)]...$(RESET)"
	@docker compose exec -w /var/www/html/app php \
	  composer install \
	  $(if $(filter prod,$(ENV)),--no-dev --optimize-autoloader,)
	@echo "$(GREEN)  ✔ Зависимости установлены$(RESET)"

console: ## Выполнить команду Symfony: make console CMD="cache:clear" [ENV=...]
	@$(PHP_ENV) bin/console $(CMD)

migrate: ## Применить миграции: make migrate [ENV=...]
	@echo "$(CYAN)▶ Применение миграций [APP_ENV=$(SYMFONY_ENV)]...$(RESET)"
	@$(PHP_ENV) bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration
	@echo "$(GREEN)  ✔ Готово$(RESET)"

fixtures: ## Загрузить фикстуры (только local)
	@if [ "$(ENV)" = "prod" ]; then \
		echo "$(RED)  ✘ Фикстуры недоступны в prod-окружении$(RESET)"; exit 1; \
	fi
	@echo "$(CYAN)▶ Загрузка фикстур...$(RESET)"
	@$(PHP_ENV) bin/console doctrine:fixtures:load --no-interaction
	@echo "$(GREEN)  ✔ Готово$(RESET)"

cache-clear: ## Очистить кеш Symfony: make cache-clear [ENV=...]
	@echo "$(CYAN)▶ Очистка кеша [APP_ENV=$(SYMFONY_ENV)]...$(RESET)"
	@$(PHP_ENV) bin/console cache:clear
	@echo "$(GREEN)  ✔ Готово$(RESET)"

# ─── Linters ──────────────────────────────────────────────────────────────────

cs-check: ## Проверить стиль кода (dry-run)
	@echo "$(CYAN)  → PHP CS Fixer (dry-run)...$(RESET)"
	@$(BIN)/php-cs-fixer fix src --dry-run --diff --ansi; \
	  if [ $$? -eq 0 ]; then echo "$(GREEN)  ✔ Стиль кода в порядке$(RESET)"; \
	  else echo "$(RED)  ✘ Нарушения стиля. Запустите: make cs-fix$(RESET)"; exit 1; fi

cs-fix: ## Автоматически исправить стиль кода
	@echo "$(CYAN)  → PHP CS Fixer (fix)...$(RESET)"
	@$(BIN)/php-cs-fixer fix src --ansi
	@echo "$(GREEN)  ✔ Стиль кода исправлен$(RESET)"

phpstan: ## Запустить статический анализ PHPStan
	@echo "$(CYAN)  → PHPStan (level 6)...$(RESET)"
	@$(BIN)/phpstan analyse src --ansi --memory-limit=256M; \
	  if [ $$? -eq 0 ]; then echo "$(GREEN)  ✔ Статический анализ пройден$(RESET)"; \
	  else echo "$(RED)  ✘ PHPStan нашёл ошибки$(RESET)"; exit 1; fi

lint: ## Запустить все линтеры (cs-check + phpstan)
	@echo "$(BOLD)  Линтеры:$(RESET)"
	@$(MAKE) cs-check
	@$(MAKE) phpstan
	@echo "$(BOLD)$(GREEN)  ✔ Все проверки пройдены$(RESET)"

test: ## Запустить тесты PHPUnit (когда появятся)
	@echo "$(CYAN)  → PHPUnit...$(RESET)"
	@$(BIN)/phpunit --colors=always; \
	  if [ $$? -eq 0 ]; then echo "$(GREEN)  ✔ Тесты пройдены$(RESET)"; \
	  else echo "$(RED)  ✘ Есть упавшие тесты$(RESET)"; exit 1; fi

# ─── Internal ─────────────────────────────────────────────────────────────────

_wait-db:
	@i=0; \
	until docker exec tg_bot-db-1 mariadb -u$${MARIADB_USER:-tg_bot_user} \
	        -p$${MARIADB_PASSWORD:-secret_password} \
	        -e "SELECT 1" >/dev/null 2>&1; do \
	  i=$$((i+1)); \
	  if [ $$i -ge 30 ]; then \
	    echo "$(RED)  ✘ БД не ответила за 30 секунд$(RESET)"; exit 1; \
	  fi; \
	  printf "$(YELLOW)    Ожидание БД... (%d/30)\r$(RESET)" $$i; \
	  sleep 1; \
	done; \
	echo "$(GREEN)  ✔ База данных готова$(RESET)"

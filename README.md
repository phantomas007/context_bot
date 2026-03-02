# Contextbot
Краткое описание сервиса

AI-сервис для анализа групповых чатов в Telegram, который:

принимает сообщения из групп через бота

сохраняет их в базу данных

агрегирует обсуждения за выбранный период

отправляет их в языковую модель (LLM)

формирует краткое и структурированное саммари

автоматически публикует сводку в чат (например, раз в 3 часа)

отправляет персональные дайджесты пользователям в личные сообщения по выбранной ими периодичности

🎯 По сути это:

AI-ассистент для групп, который:

структурирует хаотичные обсуждения

экономит время участников

позволяет “не читать 500 сообщений”

даёт персональные дайджесты

поддерживает регулярные авто-сводки в сам чат

Symfony 7.4 · PHP 8.3 · MariaDB 11.3 · Docker · GitHub Actions CI/CD

## Стек

| Сервис | Образ                | Назначение  |
|--------|----------------------|-------------|
| nginx  | `nginx:1.27-alpine`  | Веб-сервер  |
| php    | `php:8.3-fpm-alpine` | PHP-FPM     |
| db     | `mariadb:11.3`       | База данных |

---

## Быстрый старт (локально)

### 1. Клонировать и настроить переменные окружения

```bash
git clone <repo-url>
cd <папка проекта>

cp .env.example .env
```

Отредактируйте `.env` при необходимости (пароли, имя БД).

### 2. Запустить проект

**Linux / macOS:**

```bash
make run
```

**Windows PowerShell** (первый запуск — одноразово):

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
.\make run
```

Приложение будет доступно по адресу **http://localhost**

---

## Окружения

| Аргумент | APP_ENV | APP_DEBUG | Фикстуры | Кеш          |
|----------|---------|-----------|----------|--------------|
| `local`  | `dev`   | `1`       | ✔        | —            |
| `prod`   | `prod`  | `0`       | ✘        | cache:warmup |

```bash
make run              # ENV=local (по умолчанию)
make run ENV=prod     # prod-режим
```

---

## Все команды

```bash
make help                       # список всех команд

make run                        # полный запуск (local)
make run ENV=prod               # запуск в prod
make stop                       # остановить контейнеры
make restart                    # перезапустить PHP-контейнер

make migrate                    # применить миграции
make fixtures                   # перезагрузить фикстуры (только local)
make cache-clear                # очистить кеш
make console CMD="cache:warmup" # любая bin/console команда

make composer-install           # установить зависимости (local)
make composer-install ENV=prod  # без dev-пакетов

make lint                       # cs-check + phpstan
make cs-check                   # проверить стиль кода (dry-run)
make cs-fix                     # автоисправить стиль кода
make phpstan                    # статический анализ
```

---

## Файлы окружения

```
project/
├── .env                        # Docker-переменные — НЕ в git (создаётся из .env.example)
├── .env.example                # шаблон — в git
│
app/
├── .env                        # Symfony: базовые значения — в git
├── .env.local.example          # шаблон для local-разработки — в git
├── .env.local                  # DATABASE_URL через Docker-переменные — НЕ в git
├── .env.prod                   # prod: APP_DEBUG=0 — в git
├── .env.prod.local.example     # шаблон prod-секретов — в git
└── .env.prod.local             # реальные prod-секреты — НЕ в git
```

### Корневой `.env` (создаётся из `.env.example`)

```dotenv
APP_ENV=prod
APP_DEBUG=0

NGINX_SERVER_NAME=localhost      # домен для nginx (localhost — local, домен — prod)

MARIADB_DATABASE=blog
MARIADB_USER=blog_user
MARIADB_PASSWORD=secret
MARIADB_ROOT_PASSWORD=root_secret
```

### Как DATABASE_URL попадает в приложение

```
root/.env  →  MARIADB_USER, MARIADB_PASSWORD, ...
    ↓ docker-compose.yml
PHP-контейнер (env):  DB_HOST=db, DB_DATABASE=..., DB_USERNAME=..., DB_PASSWORD=...
    ↓ app/.env.local (Symfony Dotenv)
DATABASE_URL="mysql://${DB_USERNAME}:${DB_PASSWORD}@${DB_HOST}:3306/${DB_DATABASE}?..."
```

Команда `make run` автоматически создаёт `app/.env.local` из шаблона при первом запуске.

---

## CI/CD (GitHub Actions)

### CI — запускается на каждый push/PR в `main` и `develop`

Файл: `.github/workflows/ci.yml`

Шаги: установка зависимостей → PHP CS Fixer → PHPStan → миграции → фикстуры.

### CD — автоматический деплой на сервер при пуше в `main`

Файл: `.github/workflows/cd.yml`

Шаги:
1. Патч `.env` на сервере (`APP_ENV=prod`, `APP_DEBUG=0`, `NGINX_SERVER_NAME` если нет)
2. `git pull origin main`
3. `docker compose build php`
4. `docker compose up -d`
5. `composer install --no-dev --optimize-autoloader`
6. Миграции + `cache:warmup`

### Необходимые GitHub Secrets (Settings → Secrets → environment: production)

| Secret            | Описание                          |
|-------------------|-----------------------------------|
| `SSH_HOST`        | IP или хост сервера               |
| `SSH_USER`        | SSH-пользователь                  |
| `SSH_PRIVATE_KEY` | Приватный SSH-ключ                |
| `SSH_PORT`        | SSH-порт (обычно `22`)            |
| `DEPLOY_PATH`     | Путь к проекту на сервере         |

---

## Настройка production-сервера (один раз)

### 1. Клонировать репозиторий

```bash
git clone <repo-url> /path/to/project
cd /path/to/project
```

### 2. Создать корневой `.env`

```bash
cp .env.example .env
```

Заполнить реальными значениями:

```dotenv
APP_ENV=prod
APP_DEBUG=0

NGINX_SERVER_NAME=yourdomain.com   # ← ваш домен

MARIADB_DATABASE=blog
MARIADB_USER=blog_user
MARIADB_PASSWORD=strong_password
MARIADB_ROOT_PASSWORD=strong_root_password
```

### 3. Создать `app/.env.prod.local`

```bash
cp app/.env.prod.local.example app/.env.prod.local
```

Заполнить:

```dotenv
APP_SECRET=сгенерированная_строка_32_символа
```

Сгенерировать `APP_SECRET`:

```bash
php -r "echo bin2hex(random_bytes(16));"
```

### 4. Первый запуск

```bash
make run ENV=prod
```

После этого все последующие деплои выполняет CD автоматически при пуше в `main`.

---

## Структура проекта

```
project/
├── app/                        # Symfony-приложение
│   ├── src/
│   │   ├── Controller/         # BlogController, Admin/PostController, SecurityController
│   │   ├── Entity/             # User, Post, Category
│   │   ├── Form/               # PostType
│   │   ├── Repository/
│   │   └── DataFixtures/       # AppFixtures
│   ├── migrations/
│   ├── templates/              # Twig-шаблоны
│   ├── config/
│   ├── .env, .env.prod
│   ├── .php-cs-fixer.dist.php
│   └── phpstan.neon
├── docker/
│   ├── php/Dockerfile          # PHP 8.3-fpm-alpine
│   └── nginx/
│       └── default.conf.template   # Nginx vhost (домен через ${NGINX_SERVER_NAME})
├── .github/
│   └── workflows/
│       ├── ci.yml              # CI: lint + tests
│       └── cd.yml              # CD: деплой на сервер
├── docker-compose.yml
├── Makefile
├── .env.example
└── README.md
```

---

## Тестовые данные (фикстуры)

После `make run` в БД будет:

| Таблица         | Записей |
|-----------------|---------|
| `blog_user`     | 5       |
| `blog_category` | 5       |
| `blog_post`     | 30      |

**Администратор:** `admin@example.com` / пароль: `password`

## Маршруты

| URL                 | Описание                   |
|---------------------|----------------------------|
| `/`                 | Список постов              |
| `/category/{slug}`  | Посты по категории         |
| `/post/{slug}`      | Страница поста             |
| `/login`            | Вход                       |
| `/register`         | Регистрация                |
| `/admin/post/`      | Список постов (ROLE_ADMIN) |
| `/admin/post/new`   | Создать пост (ROLE_ADMIN)  |

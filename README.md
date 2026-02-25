#Symfony Blog

Symfony 7.4 · PHP 8.3 · MariaDB 11.3 · Docker

## Стек

| Сервис   | Образ                  | Назначение              |
|----------|------------------------|-------------------------|
| nginx    | `nginx:1.27-alpine`    | Веб-сервер              |
| php      | `php:8.3-fpm-alpine`   | PHP-FPM                 |
| db       | `mariadb:11.3`         | База данных             |

---

## Быстрый старт

### 1. Клонировать и настроить переменные окружения

```bash
git clone <repo-url>
cd tg_bot

# Переменные Docker (MariaDB credentials и т.д.)
cp .env.example .env
```

Отредактируйте `.env` при необходимости (пароли, имя БД).

### 2. Запустить проект

**Windows PowerShell** (первый запуск — одноразово разрешить скрипты):

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Затем:

```powershell
.\make run          # PowerShell и CMD (использует make.cmd → make.ps1)
.\make.ps1 run      # или напрямую через PowerShell-скрипт
```

> PowerShell не запускает программы из текущей директории без `.\` — это намеренное поведение безопасности.
> Всегда используйте `.\make` (не `make`) в PowerShell.

```bash
# Linux / macOS / CI
make run
```

Приложение будет доступно по адресу **http://localhost**

---

## Окружения

Команда `run` принимает аргумент `-ENV` (PowerShell) или `ENV=` (make):

| Аргумент | APP_ENV | APP_DEBUG | Фикстуры | Кеш          |
|----------|---------|-----------|----------|--------------|
| `local`  | `dev`   | `1`       | ✔        | cache:clear  |
| `prod`   | `prod`  | `0`       | ✘        | cache:warmup |

```powershell
.\make run              # local (по умолчанию)
.\make run -ENV prod    # prod-окружение
```

```bash
make run                # ENV=local (по умолчанию)
make run ENV=prod
```

---

## Все команды

### Windows (PowerShell)

```powershell
.\make help             # список всех команд

# Управление проектом
.\make run              # полный запуск (local)
.\make run -ENV prod    # запуск в prod
.\make stop             # остановить контейнеры
.\make restart          # перезапустить PHP-контейнер

# Symfony
.\make migrate                        # применить миграции
.\make fixtures                       # перезагрузить фикстуры (только local)
.\make cache-clear                    # очистить кеш
.\make console -CMD "cache:warmup"    # любая bin/console команда

# Линтеры
.\make lint             # cs-check + phpstan
.\make cs-check         # проверить стиль кода (dry-run)
.\make cs-fix           # автоисправить стиль кода
.\make phpstan          # статический анализ
```

### Linux / macOS

```bash
make help

make run                        # полный запуск
make run ENV=prod               # запуск в prod
make stop                       # остановить контейнеры

make migrate                    # применить миграции
make fixtures                   # перезагрузить фикстуры
make cache-clear                # очистить кеш
make console CMD="cache:warmup" # любая bin/console команда

make lint                       # cs-check + phpstan
make cs-fix                     # автоисправить стиль кода
```

---

## Файлы окружения

```
tg_bot/
├── .env                        # Docker-переменные (MariaDB, DB_HOST и др.) — в git
├── .env.example                # шаблон для .env — в git
│
app/
├── .env                        # Symfony: базовые значения (APP_ENV, APP_SECRET) — в git
├── .env.local.example          # шаблон .env.local с DATABASE_URL — в git
├── .env.local                  # DATABASE_URL через переменные Docker — НЕ в git
├── .env.prod                   # prod-настройки (APP_DEBUG=0) — в git
└── .env.prod.local.example     # шаблон prod-секретов — в git
    .env.prod.local             # реальные prod-секреты — НЕ в git
```

**Порядок загрузки Symfony** (каждый следующий переопределяет предыдущий):

```
.env  →  .env.local  →  .env.$APP_ENV  →  .env.$APP_ENV.local
```

### Как DATABASE_URL попадает в приложение

```
root/.env                         →  MARIADB_USER, MARIADB_PASSWORD, ...
    ↓ docker-compose.yml
PHP-контейнер (env vars):         →  DB_HOST=db, DB_DATABASE=blog,
                                      DB_USERNAME=blog_user, DB_PASSWORD=...
    ↓ app/.env.local (Symfony Dotenv)
DATABASE_URL="mysql://${DB_USERNAME}:${DB_PASSWORD}@${DB_HOST}:3306/${DB_DATABASE}?..."
```

Команда `.\make run` автоматически создаёт `app/.env.local` из шаблона при первом запуске.

### Настройка для prod

```bash
cp app/.env.prod.local.example app/.env.prod.local
# Заполнить APP_SECRET и DATABASE_URL реальными значениями
```

Сгенерировать `APP_SECRET`:
```bash
docker exec -w /var/www/html/app tg_bot-php-1 \
  php -r "echo bin2hex(random_bytes(16));"
```

---

## Структура проекта

```
tg_bot/
├── app/                        # Symfony-приложение
│   ├── src/
│   │   ├── Controller/         # BlogController, Admin/PostController, SecurityController
│   │   ├── Entity/             # User, Post, Category
│   │   ├── Form/               # PostType
│   │   ├── Repository/
│   │   └── DataFixtures/       # AppFixtures (фейковые данные)
│   ├── migrations/             # Doctrine-миграции
│   ├── templates/              # Twig-шаблоны
│   ├── config/
│   ├── .env, .env.prod
│   ├── .php-cs-fixer.dist.php  # конфиг PHP CS Fixer
│   └── phpstan.neon            # конфиг PHPStan (уровень 6)
├── docker/
│   ├── php/Dockerfile          # PHP 8.3-fpm-alpine
│   └── nginx/default.conf      # Nginx vhost
├── docker-compose.yml
├── .env, .env.example
├── Makefile                    # для Linux/macOS/CI
└── make.ps1                    # для Windows PowerShell
```

---

## Тестовые данные (фикстуры)

После `make run` в БД будет:

| Таблица        | Записей |
|----------------|---------|
| `blog_user`    | 5       |
| `blog_category`| 5       |
| `blog_post`    | 30      |

**Администратор:** `admin@example.com` / пароль: `password`

Маршруты приложения:

| URL                    | Описание                      |
|------------------------|-------------------------------|
| `/`                    | Список постов                 |
| `/category/{slug}`     | Посты по категории            |
| `/post/{slug}`         | Страница поста                |
| `/login`               | Вход                          |
| `/register`            | Регистрация                   |
| `/admin/post/`         | Список постов (ROLE_ADMIN)    |
| `/admin/post/new`      | Создать пост (ROLE_ADMIN)     |

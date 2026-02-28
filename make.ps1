param(
    [Parameter(Position=0)]
    [string]$Command = "help",

    [string]$ENV = "local",

    [string]$CMD = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

# ─── Цвета ────────────────────────────────────────────────────────────────────
function Write-Step  { param([string]$msg) Write-Host "  » $msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$msg) Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Fail  { param([string]$msg) Write-Host "  ✗ $msg" -ForegroundColor Red; exit 1 }
function Write-Info  { param([string]$msg) Write-Host "  i $msg" -ForegroundColor Yellow }
function Write-Title { param([string]$msg) Write-Host "`n══ $msg ══" -ForegroundColor Magenta }

# ─── Окружение ────────────────────────────────────────────────────────────────
$validEnvs = @("local", "prod")
if ($ENV -notin $validEnvs) {
    Write-Fail "Неизвестное окружение: '$ENV'. Допустимые: local, prod"
}

$IS_PROD    = ($ENV -eq "prod")
$APP_ENV    = if ($IS_PROD) { "prod" } else { "dev" }
$APP_DEBUG  = if ($IS_PROD) { "0"    } else { "1"   }

$EXEC_BASE = "docker compose exec -e APP_ENV=$APP_ENV -e APP_DEBUG=$APP_DEBUG -w /var/www/html/app php"

# ─── Вспомогательные функции ──────────────────────────────────────────────────
function Exec-Docker {
    param([string]$cmd)
    Invoke-Expression "$EXEC_BASE $cmd"
    if ($LASTEXITCODE -ne 0) { Write-Fail "Команда завершилась с ошибкой: $cmd" }
}

function Read-DotEnv {
    $vars = @{}
    if (Test-Path ".env") {
        Get-Content ".env" | ForEach-Object {
            if ($_ -match "^\s*([^#][^=]*)\s*=\s*(.*)\s*$") {
                $vars[$Matches[1].Trim()] = $Matches[2].Trim()
            }
        }
    }
    return $vars
}

function Wait-ForDb {
    $dotenv  = Read-DotEnv
    $dbUser  = $dotenv["MARIADB_USER"]
    $dbPass  = $dotenv["MARIADB_PASSWORD"]

    Write-Step "Жду готовности базы данных..."
    $i = 0
    while ($true) {
        $null = docker compose exec -T db mariadb -u"$dbUser" -p"$dbPass" -e "SELECT 1" 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Ok "База данных готова"; break }
        $i++
        if ($i -ge 30) { Write-Fail "БД не ответила за 30 секунд" }
        Write-Host "    Ожидание БД... ($i/30)`r" -NoNewline -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }
}

# ─── Команды ──────────────────────────────────────────────────────────────────

function Cmd-Run {
    Write-Title "Запуск проекта [ENV=$ENV | APP_ENV=$APP_ENV | APP_DEBUG=$APP_DEBUG]"

    # Проверяем наличие app/.env.local
    if (-not (Test-Path "app/.env.local")) {
        if (Test-Path "app/.env.local.example") {
            Copy-Item "app/.env.local.example" "app/.env.local"
            Write-Ok "Создан app/.env.local из app/.env.local.example"
        } else {
            Write-Fail "Файл app/.env.local не найден и нет шаблона app/.env.local.example"
        }
    }

    # Передаём APP_ENV и APP_DEBUG в docker compose через переменные окружения процесса.
    # docker compose читает их при подстановке ${APP_ENV:-dev} в docker-compose.yml
    # и пересоздаёт контейнер если значения изменились (local→prod или prod→local).
    $env:APP_ENV   = $APP_ENV
    $env:APP_DEBUG = $APP_DEBUG

    Write-Step "Сборка образов (только изменённые)..."
    docker compose build
    if ($LASTEXITCODE -ne 0) { Write-Fail "docker compose build завершился с ошибкой" }
    Write-Ok "Образы актуальны"

    Write-Step "Запуск контейнеров [APP_ENV=$APP_ENV, APP_DEBUG=$APP_DEBUG]..."
    docker compose up -d
    if ($LASTEXITCODE -ne 0) { Write-Fail "docker compose up завершился с ошибкой" }
    Write-Ok "Контейнеры запущены"

    Wait-ForDb

    Write-Step "Устанавливаю зависимости Composer"
    if ($IS_PROD) {
        Exec-Docker "composer install --no-dev --optimize-autoloader --no-interaction"
    } else {
        Exec-Docker "composer install --no-interaction"
    }
    Write-Ok "Зависимости установлены"

    Write-Step "Применяю миграции"
    Exec-Docker "php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration"
    Write-Ok "Миграции выполнены"

    if ($IS_PROD) {
        Write-Step "Прогреваю кеш (prod)"
        Exec-Docker "php bin/console cache:warmup"
        Write-Ok "Кеш прогрет"
    } else {
        Write-Step "Загружаю фикстуры"
        Exec-Docker "php bin/console doctrine:fixtures:load --no-interaction"
        Write-Ok "Фикстуры загружены"

        Write-Step "Очищаю кеш"
        Exec-Docker "php bin/console cache:clear"
        Write-Ok "Кеш очищен"
    }

    if (-not $IS_PROD) {
        Write-Title "Линтеры"
        Cmd-Lint
    } else {
        Write-Info "Линтеры пропущены в prod (dev-зависимости не установлены)"
    }

    Write-Title "Готово"
    Write-Ok "Приложение доступно: http://localhost"
}

function Cmd-Stop {
    Write-Title "Остановка контейнеров"
    docker compose stop
    Write-Ok "Контейнеры остановлены"
}

function Cmd-DbReset {
    Write-Title "Сброс базы данных (удаление тома)"
    Write-Info "Останавливаю контейнеры и удаляю том tg_bot_db_data..."
    docker compose down -v
    if ($LASTEXITCODE -ne 0) { Write-Fail "Не удалось остановить контейнеры" }
    Write-Ok "Том удалён — БД будет пересоздана при следующем .\make run"
}

function Cmd-Restart {
    Write-Title "Перезапуск PHP-контейнера"
    docker compose restart php
    Write-Ok "PHP-контейнер перезапущен"
}

function Cmd-Migrate {
    Write-Title "Миграции [ENV=$ENV]"
    Exec-Docker "php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration"
    Write-Ok "Миграции выполнены"
}

function Cmd-Fixtures {
    if ($IS_PROD) {
        Write-Fail "Фикстуры недоступны в prod-окружении"
    }
    Write-Title "Загрузка фикстур [ENV=$ENV]"
    Exec-Docker "php bin/console doctrine:fixtures:load --no-interaction"
    Write-Ok "Фикстуры загружены"
}

function Cmd-CacheClear {
    Write-Title "Очистка кеша [ENV=$ENV]"
    Exec-Docker "php bin/console cache:clear"
    Write-Ok "Кеш очищен"
}

function Cmd-Console {
    if (-not $CMD) {
        Write-Fail "Укажите команду: .\make console -CMD 'cache:clear'"
    }
    Write-Title "bin/console $CMD"
    Exec-Docker "php bin/console $CMD"
}

function Cmd-CsCheck {
    Write-Title "PHP CS Fixer (dry-run)"
    Exec-Docker "composer cs-check"
    Write-Ok "Стиль кода в порядке"
}

function Cmd-CsFix {
    Write-Title "PHP CS Fixer (fix)"
    Exec-Docker "composer cs-fix"
    Write-Ok "Стиль кода исправлен"
}

function Cmd-Phpstan {
    Write-Title "PHPStan"
    Exec-Docker "composer phpstan"
    Write-Ok "PHPStan: ошибок не найдено"
}

function Cmd-Lint {
    Write-Step "Запускаю PHP CS Fixer (dry-run)..."
    $csResult = docker compose exec -e APP_ENV=$APP_ENV -e APP_DEBUG=$APP_DEBUG -w /var/www/html/app php composer cs-check 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host $csResult
        Write-Fail "Нарушения стиля. Запустите: .\make cs-fix"
    }
    Write-Ok "CS Fixer: OK"

    Write-Step "Запускаю PHPStan..."
    $stanResult = docker compose exec -e APP_ENV=$APP_ENV -e APP_DEBUG=$APP_DEBUG -w /var/www/html/app php composer phpstan 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host $stanResult
        Write-Fail "PHPStan нашёл ошибки"
    }
    Write-Ok "PHPStan: OK"
}

function Cmd-Help {
    Write-Host ""
    Write-Host "  Использование: " -NoNewline
    Write-Host ".\make <команда> [-ENV local|prod]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Окружения (-ENV):" -ForegroundColor Yellow
    Write-Host "    local  ->  APP_ENV=dev,  APP_DEBUG=1, фикстуры загружаются  (по умолчанию)"
    Write-Host "    prod   ->  APP_ENV=prod, APP_DEBUG=0, фикстуры НЕ загружаются, cache warmup"
    Write-Host ""
    Write-Host "  Основное:" -ForegroundColor Yellow
    $cmds = @(
        @{ name = "run";          desc = "Сборка/старт + миграции + фикстуры (или warmup) + линтеры" },
        @{ name = "stop";         desc = "Остановить все контейнеры" },
        @{ name = "restart";      desc = "Перезапустить PHP-контейнер" },
        @{ name = "db-reset";     desc = "Удалить том БД (если сменили пароли в .env)" }
    )
    foreach ($c in $cmds) {
        Write-Host "    " -NoNewline
        Write-Host ("{0,-14}" -f $c.name) -ForegroundColor Cyan -NoNewline
        Write-Host $c.desc
    }
    Write-Host ""
    Write-Host "  Symfony:" -ForegroundColor Yellow
    $cmds2 = @(
        @{ name = "migrate";      desc = "Применить миграции" },
        @{ name = "fixtures";     desc = "Загрузить фикстуры (только local)" },
        @{ name = "cache-clear";  desc = "Очистить кеш" },
        @{ name = "console";      desc = "Консольная команда: .\make console -CMD 'cache:clear'" }
    )
    foreach ($c in $cmds2) {
        Write-Host "    " -NoNewline
        Write-Host ("{0,-14}" -f $c.name) -ForegroundColor Cyan -NoNewline
        Write-Host $c.desc
    }
    Write-Host ""
    Write-Host "  Линтеры:" -ForegroundColor Yellow
    $cmds3 = @(
        @{ name = "lint";         desc = "Все линтеры (cs-check + phpstan)" },
        @{ name = "cs-check";     desc = "Проверить стиль кода (dry-run)" },
        @{ name = "cs-fix";       desc = "Автоматически исправить стиль" },
        @{ name = "phpstan";      desc = "Статический анализ PHPStan" }
    )
    foreach ($c in $cmds3) {
        Write-Host "    " -NoNewline
        Write-Host ("{0,-14}" -f $c.name) -ForegroundColor Cyan -NoNewline
        Write-Host $c.desc
    }
    Write-Host ""
    Write-Host "  Примеры:" -ForegroundColor Yellow
    Write-Host "    " -NoNewline; Write-Host ".\make run" -ForegroundColor Cyan -NoNewline; Write-Host "               # local (по умолчанию)"
    Write-Host "    " -NoNewline; Write-Host ".\make run -ENV prod" -ForegroundColor Cyan -NoNewline; Write-Host "        # prod (без фикстур, с cache warmup)"
    Write-Host "    " -NoNewline; Write-Host ".\make migrate -ENV prod" -ForegroundColor Cyan -NoNewline; Write-Host "    # миграции в prod"
    Write-Host ""
}

# ─── Диспетчер ────────────────────────────────────────────────────────────────
switch ($Command) {
    "run"         { Cmd-Run }
    "stop"        { Cmd-Stop }
    "restart"     { Cmd-Restart }
    "db-reset"    { Cmd-DbReset }
    "migrate"     { Cmd-Migrate }
    "fixtures"    { Cmd-Fixtures }
    "cache-clear" { Cmd-CacheClear }
    "console"     { Cmd-Console }
    "cs-check"    { Cmd-CsCheck }
    "cs-fix"      { Cmd-CsFix }
    "phpstan"     { Cmd-Phpstan }
    "lint"        { Cmd-Lint }
    "help"        { Cmd-Help }
    default {
        Write-Host "  x Неизвестная команда: '$Command'" -ForegroundColor Red
        Write-Host "  Запустите " -NoNewline; Write-Host ".\make help" -ForegroundColor Cyan -NoNewline; Write-Host " для списка команд"
        exit 1
    }
}

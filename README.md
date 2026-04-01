# Telemt MTProxy Installer

Автоматическая установка [Telemt](https://github.com/telemt/telemt) MTProxy для Telegram одним скриптом.

Два режима: **Docker** (рекомендуется) или **нативный бинарник**. Все настройки telemt `config.toml` доступны через интерактивное меню или переменные окружения.

---

> **Вопросы, помощь, предложения** — пишите в Telegram: [@arblark](https://t.me/arblark)

---

## Возможности

- **Готовые профили** — выбор конфигурации одной цифрой:
  - **Рекомендуемый** — TLS (ee) + Middle Proxy + TLS-эмуляция (эталон telemt)
  - **Secure** — Secure (dd) + Middle Proxy + маскировка
  - **Простой** — Classic + прямое подключение (проверенная рабочая конфигурация)
  - **Ручная настройка** — полный контроль над каждым параметром
- **Два метода установки** — Docker-контейнер или нативный бинарник с systemd
- **Интерактивный режим** — пошаговая настройка всех параметров с дефолтами
- **Авто-режим** — неинтерактивная установка через `--auto` с переменными окружения
- **Полная конфигурация telemt** — все параметры `config.toml` настраиваются в скрипте:
  - TLS-маскировка и эмуляция сертификатов
  - Режимы протокола (classic, secure, TLS)
  - Middle Proxy, mask_host
  - Prometheus-метрики
  - Management API
  - Множество пользователей с уникальными секретами
  - IPv4/IPv6
  - Уровень логирования
- **Автоопределение IP** сервера
- **Проверка порта** перед запуском
- **Валидация DNS** домена маскировки
- **Проверка соединения** после старта
- **QR-код** ссылки прямо в терминале
- **Firewall** — автооткрытие порта (UFW + firewalld)
- **Готовые ссылки** — `https://t.me/proxy` и `tg://proxy`
- **Сохранение конфигурации** между запусками
- **Обновление и удаление** встроенными командами
- **Редактирование** `config.toml` прямо из скрипта (`--edit`)
- **Просмотр логов** в реальном времени (`--logs`)
- **Multi-distro** — Debian, Ubuntu, CentOS, Fedora и другие

## Быстрый старт

### Установка одной командой

```bash
curl -sSL https://raw.githubusercontent.com/arblark/telemt-setup/main/telemt-setup.sh -o telemt-setup.sh && chmod +x telemt-setup.sh && sudo ./telemt-setup.sh
```

Или через `wget`:

```bash
wget -qO telemt-setup.sh https://raw.githubusercontent.com/arblark/telemt-setup/main/telemt-setup.sh && chmod +x telemt-setup.sh && sudo ./telemt-setup.sh
```

### Пошагово

1. Купите VPS/VDS (Debian, Ubuntu, CentOS — любой Linux)
2. Подключитесь: `ssh root@IP_СЕРВЕРА`
3. Скачайте и запустите:

```bash
curl -sSL https://raw.githubusercontent.com/arblark/telemt-setup/main/telemt-setup.sh -o telemt-setup.sh
chmod +x telemt-setup.sh
sudo ./telemt-setup.sh
```

4. Ответьте на вопросы (или Enter для значений по умолчанию)
5. Скопируйте ссылку или отсканируйте QR-код в Telegram

## Команды

```bash
sudo ./telemt-setup.sh                # интерактивная установка
sudo ./telemt-setup.sh --auto         # установка без вопросов
sudo ./telemt-setup.sh --status       # статус прокси
sudo ./telemt-setup.sh --show         # показать ссылки и QR-код
sudo ./telemt-setup.sh --edit         # открыть config.toml в редакторе
sudo ./telemt-setup.sh --logs         # логи в реальном времени
sudo ./telemt-setup.sh --update       # обновить telemt и перезапустить
sudo ./telemt-setup.sh --uninstall    # удалить всё
sudo ./telemt-setup.sh --help         # справка
```

## Профили конфигурации

При установке скрипт предлагает выбрать готовый профиль:

| # | Профиль | Режим | Middle Proxy | TLS-эмуляция | Для кого |
|---|---|---|---|---|---|
| 1 | **Рекомендуемый** | TLS (ee) | Да | Да | Большинство случаев, эталон telemt |
| 2 | **Secure** | Secure (dd) | Да | Нет | Быстрее, но проще для DPI |
| 3 | **Простой** | Classic | Нет | Нет | Проверенная рабочая конфигурация |
| 4 | **Ручная настройка** | Любой | Любой | Любая | Полный контроль |

Для авто-режима: `TM_PRESET=simple ./telemt-setup.sh --auto`

## Параметры конфигурации

### Основные

| Параметр | По умолчанию | Env-переменная | Описание |
|---|---|---|---|
| Метод установки | docker | `TM_METHOD` | `docker` или `binary` |
| IP сервера | автоопред. | `TM_IP` | Внешний IP вашего VDS/VPS |
| Порт | 443 | `TM_PORT` | Порт для подключения клиентов |
| TLS-домен | apple.com | `TM_TLS_DOMAIN` | Домен маскировки трафика |

### Маскировка и TLS

| Параметр | По умолчанию | Env-переменная | Описание |
|---|---|---|---|
| Маскировка | true | `TM_MASK` | Forward нераспознанного трафика на TLS-домен |
| TLS-эмуляция | true | `TM_TLS_EMULATION` | Эмуляция реальных длин TLS-записей |

### Режимы протокола

| Параметр | По умолчанию | Env-переменная | Описание |
|---|---|---|---|
| Classic | false | `TM_MODE_CLASSIC` | Без обфускации |
| Secure | false | `TM_MODE_SECURE` | С `dd`-префиксом |
| TLS | true | `TM_MODE_TLS` | С `ee`-префиксом + SNI (по умолчанию) |

### Сеть и Middle Proxy

| Параметр | По умолчанию | Env-переменная | Описание |
|---|---|---|---|
| Middle Proxy | true | `TM_MIDDLE_PROXY` | Подключение через Middle Proxy Telegram |
| IPv6 | false | `TM_IPV6` | Слушать IPv6 в дополнение к IPv4 |

### Мониторинг

| Параметр | По умолчанию | Env-переменная | Описание |
|---|---|---|---|
| Метрики | false | `TM_METRICS` | Prometheus-метрики |
| Порт метрик | 9090 | `TM_METRICS_PORT` | Порт эндпоинта метрик |
| API | true | `TM_API` | Management API |
| Порт API | 9091 | `TM_API_PORT` | Порт Management API |

### Логирование

| Параметр | По умолчанию | Env-переменная | Описание |
|---|---|---|---|
| Уровень логов | normal | `TM_LOG_LEVEL` | `debug`, `verbose`, `normal`, `silent` |

### Ссылки и контейнер

| Параметр | По умолчанию | Env-переменная | Описание |
|---|---|---|---|
| Публичный хост | авто (IP) | `TM_PUBLIC_HOST` | Хост для генерации tg:// ссылок |
| Публичный порт | порт сервера | `TM_PUBLIC_PORT` | Порт для генерации ссылок |
| Имя контейнера | telemt | `TM_CONTAINER` | Имя Docker-контейнера |
| Версия telemt | latest | `TELEMT_VERSION` | Версия для установки |

## Авто-режим

Для автоматизации (Ansible, cloud-init, скрипты) используйте `--auto`:

```bash
sudo TM_PRESET=simple TM_PORT=443 TM_METHOD=docker ./telemt-setup.sh --auto
```

Или с полной настройкой:

```bash
sudo TM_PORT=8443 TM_TLS_DOMAIN=google.com TM_METHOD=binary ./telemt-setup.sh --auto
```

Все параметры из env-переменных, без интерактивных вопросов.

## Конфигурация после установки

Скрипт генерирует полный `config.toml` в `/etc/telemt/telemt.toml`. Для ручной правки:

```bash
sudo ./telemt-setup.sh --edit
```

Или напрямую:

```bash
sudo nano /etc/telemt/telemt.toml
# Затем перезапустить:
sudo docker restart telemt       # для Docker
sudo systemctl restart telemt    # для бинарника
```

## Результат установки

```
╔══════════════════════════════════════════════════════════╗
║  Установка завершена!                                    ║
╚══════════════════════════════════════════════════════════╝

  Метод:         docker
  Сервер:        203.0.113.1
  Порт:          443
  TLS-домен:     apple.com
  Маскировка:    true
  TLS-эмуляция:  true

──────────────────────────────────────────────────────────
  Ссылки для подключения в Telegram (TLS/ee):

  user1:
    https://t.me/proxy?server=203.0.113.1&port=443&secret=ee...

──────────────────────────────────────────────────────────
  QR-код (user1):
  █████████████████████
  █ ▄▄▄▄▄ █ ... █ ▄▄▄▄▄ █
  ...
```

## Docker vs Binary

| | Docker | Binary |
|---|---|---|
| Установка | Автоматическая | Автоматическая |
| Изоляция | Полная (контейнер) | Отдельный пользователь + systemd |
| Обновление | `--update` (pull + restart) | `--update` (скачать + restart) |
| Безопасность | read-only, cap-drop, no-new-privileges | RAII, capabilities, ProtectSystem |
| Ресурсы | +50 МБ Docker overhead | Минимальные |

## Требования

- Linux (Debian / Ubuntu / CentOS / Fedora / и др.)
- Root-доступ (sudo)
- Доступ в интернет

## Лицензия

MIT

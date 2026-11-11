# Сборка и выпуск

## Локальная сборка

Требуются macOS 13 или новее и Apple Command Line Tools со Swift.

```sh
./build.sh
open "build/Winamp Classic.app"
```

По умолчанию собирается arm64-приложение с локальной ad-hoc подписью. Для Intel или Universal задайте архитектуры:

```sh
WINAMP_ARCHS=x86_64 ./build.sh
WINAMP_ARCHS="arm64 x86_64" ./build.sh
```

## Функциональная проверка

```sh
"build/Winamp Classic.app/Contents/MacOS/WinampClassic" --smoke-test
```

Проверка создаёт двухсекундный WAV в `/tmp`, проверяет загрузку, воспроизведение, паузу, перемотку, изменение полосы EQ, bypass, продолжение, остановку, удаление записи и отрисовку окна. Снимок окна сохраняется в `/tmp/winamp-preview.png`.

Universal-файл проверяется на наличие обеих архитектур. Функциональная проверка выполнена на Apple Silicon; запуск на отдельном Intel Mac ещё требует проверки.

## Установочный DMG

```sh
./release.sh
```

По умолчанию создаётся Universal-сборка для Apple Silicon и Intel с macOS 13+. Результат — `dist/Winamp-Classic-1.1-Universal.dmg`, рядом сохраняются SHA-256 и описание релиза. Для отдельной архитектуры задайте `WINAMP_ARCHS=arm64` или `WINAMP_ARCHS=x86_64`.

Проверка контрольной суммы:

```sh
cd dist
shasum -a 256 -c Winamp-Classic-1.1-Universal.dmg.sha256
```

Без Developer ID DMG имеет ad-hoc подпись и не нотарифицирован. После скачивания Gatekeeper может заблокировать первый запуск. [Документация Apple о Developer ID](https://developer.apple.com/developer-id/).

## Подпись и нотарификация

Скрипты поддерживают Developer ID и профиль `notarytool`, хранящийся в Связке ключей:

```sh
WINAMP_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
WINAMP_NOTARY_PROFILE='winamp-notary' \
./release.sh
```

Приложение подписывается с hardened runtime и timestamp; DMG отправляется в Apple, получает билет нотарификации и проверяется через `stapler`. Профиль создаётся владельцем Apple Developer через `xcrun notarytool store-credentials`. Сертификаты, ключи и пароли не следует добавлять в репозиторий.

## GitHub Actions

[Workflow выпуска](../.github/workflows/release.yml) при ручном запуске создаёт Universal DMG как артефакт сборки. Новый тег `v*` дополнительно создаёт черновик GitHub Release, если релиз ещё не существует. Workflow не публикует релиз автоматически; без настройки Developer ID сборка остаётся ad-hoc. Перед новым тегом обновите версию в [Info.plist](../Resources/Info.plist).

[К README](../README.md).

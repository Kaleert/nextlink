## Что и зачем

Кратко: какую проблему решает PR и как меняется поведение Nextlink?

## Основные изменения

- 

## Проверки

- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings`
- [ ] `flutter test test/core/models test/core/utils test/core/engine test/core/localization --exclude-tags network`
- [ ] `python3 -m unittest discover -s test/python -v`
- [ ] `flutter build apk --debug --flavor original --target-platform android-arm64`
- [ ] Тест на Android-устройстве (если затронуты TUN / VPN / native)
- [ ] RU / UK / EN и пустые состояния UI (если изменялся интерфейс)

## Совместимость и риски

Как влияет на Original / Shadow? Меняет ли данные приложения, миграции, маршруты, разрешения?

## Скриншоты или логи (при необходимости)

Не прикладывай реальные URL подписок, ключи и неочищенные логи.

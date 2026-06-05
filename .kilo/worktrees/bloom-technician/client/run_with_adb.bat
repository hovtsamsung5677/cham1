@echo off
echo ========================================
echo Запуск через ADB reverse (рекомендуется для USB)
echo ========================================
echo.

REM Проверяем, запущен ли сервер
echo Проверка сервера...
powershell -Command "try { $response = Invoke-WebRequest -Uri 'http://localhost/health' -UseBasicParsing -TimeoutSec 2; echo OK } catch { echo FAIL }" | findstr /C:"OK" >nul
if errorlevel 1 (
    echo ОШИБКА: Сервер не запущен на localhost
    echo Запустите сначала: docker-compose up -d
    pause
    exit /b 1
)

echo Сервер работает.
echo.

REM Проверяем ADB устройство
echo Проверка подключенного Android устройства...
adb devices | findstr /C:"device" >nul
if errorlevel 1 (
    echo ОШИБКА: Устройство не найдено или отладка не включена
    echo Убедитесь, что:
    echo 1. На телефоне включена отладка по USB (Настройки -> Для разработчиков)
    echo 2. Телефон подключен по USB кабелю
    echo 3. Установлены ADB драйверы
    pause
    exit /b 1
)

echo Устройство найдено.
echo.

REM Делаем проброс портов
echo Проброс порта 80 на устройство...
adb reverse tcp:80 tcp:80
if errorlevel 1 (
    echo ОШИБКА: Не удалось выполнить adb reverse
    echo Попробуйте вручную: adb reverse tcp:80 tcp:80
    pause
    exit /b 1
)

echo Порт проброшен успешно!
echo Теперь на телефоне http://localhost будет указывать на компьютер
echo.

REM Устанавливаем зависимости
echo Установка Flutter зависимостей...
flutter pub get
if errorlevel 1 (
    echo ОШИБКА: Не удалось установить зависимости
    pause
    exit /b 1
)

REM Запускаем приложение с localhost
echo.
echo ========================================
echo Запуск приложения...
echo Сервер: http://localhost (через ADB reverse)
echo ========================================
echo.

flutter run --dart-define=SERVER_URL=http://localhost

if errorlevel 1 (
    echo.
    echo ОШИБКА: Не удалось запустить приложение
    pause
    exit /b 1
)

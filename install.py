"""
Установщик системы 1C-Sweeper.
Интерактивная настройка и развертывание.
"""

import os
import sys
import json
import subprocess
import base64
from pathlib import Path


def print_header(text):
    """Вывести заголовок."""
    print('\n' + '=' * 80)
    print(text.center(80))
    print('=' * 80 + '\n')


def print_step(step_num, total, text):
    """Вывести шаг установки."""
    print(f'\n[Шаг {step_num}/{total}] {text}')
    print('-' * 80)


def check_python_version():
    """Проверить версию Python."""
    print_step(1, 9, 'Проверка версии Python')
    
    version = sys.version_info
    print(f'Установленная версия Python: {version.major}.{version.minor}.{version.micro}')
    
    if version.major < 3 or (version.major == 3 and version.minor < 8):
        print('[ОШИБКА] Требуется Python 3.8 или выше!')
        return False
    
    print('[OK] Версия Python подходит')
    return True


def install_dependencies():
    """Установить зависимости."""
    print_step(2, 9, 'Установка зависимостей')
    
    try:
        print('Выполняется: pip install -r requirements.txt')
        subprocess.run(
            [sys.executable, '-m', 'pip', 'install', '-r', 'requirements.txt'],
            check=True
        )
        print('[OK] Зависимости установлены успешно')
        return True
    except subprocess.CalledProcessError:
        print('[ОШИБКА] Не удалось установить зависимости')
        return False


def get_input(prompt, default=None):
    """Получить ввод пользователя с возможностью значения по умолчанию."""
    if default:
        user_input = input(f'{prompt} [{default}]: ').strip()
        return user_input if user_input else default
    else:
        user_input = input(f'{prompt}: ').strip()
        return user_input


def get_yes_no(prompt, default=True):
    """Получить ответ да/нет."""
    default_str = 'Y/n' if default else 'y/N'
    user_input = input(f'{prompt} [{default_str}]: ').strip().lower()
    
    if not user_input:
        return default
    
    return user_input in ['y', 'yes', 'да', 'д']


def get_paths(prompt):
    """Получить список путей от пользователя."""
    print(f'\n{prompt}')
    print('Введите пути по одному (пустая строка для завершения):')
    
    paths = []
    while True:
        path = input(f'  Путь {len(paths) + 1}: ').strip()
        if not path:
            break
        paths.append(path)
    
    return paths


def configure_git():
    """Настроить Git-конфигурацию."""
    print_step(3, 9, 'Настройка Git-репозиториев')
    
    config = {
        'repos': [],
        'searchPaths': [],
        'sizeThresholdGB': 15
    }
    
    # Явные репозитории
    if get_yes_no('Указать конкретные Git-репозитории?', False):
        config['repos'] = get_paths('Укажите пути к репозиториям')
    
    # Пути для поиска
    if get_yes_no('Указать папки для автоматического поиска репозиториев?', True):
        config['searchPaths'] = get_paths('Укажите папки для поиска')
    
    # Порог размера
    threshold = get_input('Порог размера для обслуживания (ГБ)', '15')
    try:
        config['sizeThresholdGB'] = int(threshold)
    except ValueError:
        config['sizeThresholdGB'] = 15
    
    return config


def configure_edt():
    """Настроить EDT-конфигурацию."""
    print_step(4, 9, 'Настройка EDT workspaces')
    
    config = {
        'workspaces': [],
        'searchPaths': [],
        'sizeThresholdGB': 5
    }
    
    # Явные workspaces
    if get_yes_no('Указать конкретные EDT workspaces?', False):
        config['workspaces'] = get_paths('Укажите пути к workspaces')
    
    # Пути для поиска
    if get_yes_no('Указать папки для автоматического поиска workspaces?', True):
        config['searchPaths'] = get_paths('Укажите папки для поиска')
    
    # Порог размера
    threshold = get_input('Порог размера для обслуживания (ГБ)', '5')
    try:
        config['sizeThresholdGB'] = int(threshold)
    except ValueError:
        config['sizeThresholdGB'] = 5
    
    return config


def configure_database():
    """Настроить конфигурацию баз 1С."""
    print_step(5, 9, 'Настройка информационных баз 1С')
    
    config = {
        'databases': [],
        'searchPaths': [],
        'platformVersion': '',
        'sizeThresholdGB': 3
    }
    
    # Явные базы
    if get_yes_no('Указать конкретные базы данных (.1CD)?', False):
        config['databases'] = get_paths('Укажите пути к базам данных')
    
    # Пути для поиска
    if get_yes_no('Указать папки для автоматического поиска баз?', True):
        config['searchPaths'] = get_paths('Укажите папки для поиска')
    
    # Версия платформы
    print('\nВерсия платформы 1С (примеры: 8.3.27, 8.3.*, 8.3.2[0-9])')
    version = get_input('Маска версии платформы (пусто = любая)', '')
    if version:
        config['platformVersion'] = version
    
    # Аутентификация
    if get_yes_no('Требуется аутентификация для баз?', False):
        username = get_input('Имя пользователя')
        password = get_input('Пароль')
        
        if username:
            config['user'] = username
        if password:
            # Кодируем пароль в Base64
            password_b64 = base64.b64encode(password.encode('utf-8')).decode('utf-8')
            config['password'] = password_b64
    
    # Порог размера
    threshold = get_input('Порог размера для обслуживания (ГБ)', '3')
    try:
        config['sizeThresholdGB'] = int(threshold)
    except ValueError:
        config['sizeThresholdGB'] = 3
    
    return config


def configure_general():
    """Настроить общие параметры."""
    print_step(6, 9, 'Общие настройки')
    
    config = {
        'reportsPath': './reports',
        'silentMode': False,
        'parallelProcessing': False,
        'maxParallelTasks': 2
    }
    
    # Путь для отчетов
    reports_path = get_input('Путь для сохранения отчетов', './reports')
    config['reportsPath'] = reports_path
    
    # Тихий режим
    config['silentMode'] = get_yes_no('Использовать тихий режим по умолчанию?', False)
    
    # Параллелизм (пока отключен в этой версии)
    config['parallelProcessing'] = False
    config['maxParallelTasks'] = 2
    
    return config


def save_configuration(config):
    """Сохранить конфигурацию."""
    print_step(7, 9, 'Сохранение конфигурации')
    
    config_path = 'maintenance-config.json'
    
    try:
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        print(f'[OK] Конфигурация сохранена в {config_path}')
        return True
    except Exception as e:
        print(f'[ОШИБКА] Не удалось сохранить конфигурацию: {e}')
        return False


def create_reports_directory(reports_path):
    """Создать директорию для отчетов."""
    try:
        os.makedirs(reports_path, exist_ok=True)
        print(f'[OK] Создана директория для отчетов: {reports_path}')
        return True
    except Exception as e:
        print(f'[ОШИБКА] Не удалось создать директорию: {e}')
        return False


def setup_task_scheduler():
    """Настроить планировщик задач Windows."""
    print_step(8, 9, 'Настройка планировщика задач Windows')
    
    if not get_yes_no('Настроить автоматический запуск по расписанию?', True):
        print('[ПРОПУЩЕНО] Настройка планировщика пропущена')
        return True
    
    task_name = '1C-Sweeper-Maintenance'
    
    # Получаем абсолютный путь к скрипту
    script_dir = os.path.abspath(os.path.dirname(__file__))
    maintenance_script = os.path.join(script_dir, 'src', 'maintenance.py')
    python_exe = sys.executable
    
    # Параметры задачи
    print('\nПараметры расписания:')
    print('1. Еженедельно (воскресенье 22:00)')
    print('2. Ежедневно (22:00)')
    print('3. Ежемесячно (первое воскресенье, 22:00)')
    
    choice = get_input('Выберите вариант', '1')
    
    # Формируем команду для создания задачи
    if choice == '1':
        schedule = 'WEEKLY'
        modifier = '/D SUN /ST 22:00'
    elif choice == '2':
        schedule = 'DAILY'
        modifier = '/ST 22:00'
    else:
        schedule = 'MONTHLY'
        modifier = '/D SUN /MO FIRST /ST 22:00'
    
    # Команда для запуска
    run_command = f'"{python_exe}" "{maintenance_script}" --silent'
    
    # Создаем задачу через schtasks
    try:
        # Удаляем существующую задачу если есть
        subprocess.run(
            ['schtasks', '/Delete', '/TN', task_name, '/F'],
            capture_output=True
        )
        
        # Создаем новую задачу
        cmd = [
            'schtasks', '/Create',
            '/TN', task_name,
            '/TR', run_command,
            '/SC', schedule,
            '/F'
        ]
        
        # Добавляем модификаторы
        if choice == '1':
            cmd.extend(['/D', 'SUN', '/ST', '22:00'])
        elif choice == '2':
            cmd.extend(['/ST', '22:00'])
        else:
            cmd.extend(['/D', 'SUN', '/MO', 'FIRST', '/ST', '22:00'])
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            print(f'[OK] Задача "{task_name}" создана успешно')
            print(f'     Расписание: {schedule}')
            return True
        else:
            print(f'[ОШИБКА] Не удалось создать задачу: {result.stderr}')
            print('[СПРАВКА] Возможно требуются права администратора')
            return False
    
    except Exception as e:
        print(f'[ОШИБКА] Ошибка при создании задачи: {e}')
        return False


def run_test():
    """Выполнить тестовый запуск."""
    print_step(9, 9, 'Тестовый запуск')
    
    if not get_yes_no('Выполнить тестовый запуск?', True):
        print('[ПРОПУЩЕНО] Тестовый запуск пропущен')
        return True
    
    try:
        print('\nЗапуск системы обслуживания...\n')
        
        # Запускаем maintenance.py
        result = subprocess.run(
            [sys.executable, '-m', 'src.maintenance', '--config', 'maintenance-config.json'],
            cwd=os.path.dirname(__file__) or '.'
        )
        
        if result.returncode == 0:
            print('\n[OK] Тестовый запуск завершен успешно')
            return True
        else:
            print(f'\n[ПРЕДУПРЕЖДЕНИЕ] Тестовый запуск завершен с кодом {result.returncode}')
            return True  # Не считаем это критичной ошибкой
    
    except Exception as e:
        print(f'\n[ОШИБКА] Ошибка при тестовом запуске: {e}')
        return False


def main():
    """Главная функция установки."""
    print_header('УСТАНОВЩИК 1C-SWEEPER')
    print('Система автоматизированного обслуживания Git-репозиториев,')
    print('EDT workspaces и информационных баз 1С')
    
    # Шаг 1: Проверка Python
    if not check_python_version():
        sys.exit(1)
    
    # Шаг 2: Установка зависимостей
    if not install_dependencies():
        sys.exit(1)
    
    # Шаг 3-6: Сбор конфигурации
    git_config = configure_git()
    edt_config = configure_edt()
    db_config = configure_database()
    general_config = configure_general()
    
    # Формируем полную конфигурацию
    full_config = {
        'settings': {
            'git': git_config,
            'edt': edt_config,
            'database': db_config,
            'general': general_config
        }
    }
    
    # Шаг 7: Сохранение конфигурации
    if not save_configuration(full_config):
        sys.exit(1)
    
    # Создание директории для отчетов
    create_reports_directory(general_config['reportsPath'])
    
    # Шаг 8: Настройка планировщика
    setup_task_scheduler()
    
    # Шаг 9: Тестовый запуск
    run_test()
    
    # Финальное сообщение
    print_header('УСТАНОВКА ЗАВЕРШЕНА')
    print('[OK] Система 1C-Sweeper успешно установлена и настроена!')
    print()
    print('Для ручного запуска используйте:')
    print(f'  python -m src.maintenance')
    print()
    print('Для запуска в тихом режиме:')
    print(f'  python -m src.maintenance --silent')
    print()
    print('Конфигурация сохранена в: maintenance-config.json')
    print('Отчеты будут сохраняться в:', general_config['reportsPath'])
    print()


if __name__ == '__main__':
    main()


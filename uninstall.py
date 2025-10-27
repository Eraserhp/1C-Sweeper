"""
Деинсталлятор системы 1C-Sweeper.
Удаление конфигурации, планировщика задач и опционально файлов системы.
"""

import os
import sys
import json
import subprocess
import shutil
import argparse
from datetime import datetime
from pathlib import Path


def get_timestamp():
    """Получить текущую временную метку."""
    now = datetime.now()
    return now.strftime('[%Y-%m-%d %H:%M:%S]')


def log_message(level, message):
    """Вывести сообщение с временной меткой."""
    timestamp = get_timestamp()
    print(f'{timestamp} [{level}] {message}')


def print_header(text):
    """Вывести заголовок."""
    print('\n' + '=' * 80)
    print(text.center(80))
    print('=' * 80 + '\n')


def print_step(step_num, total, text):
    """Вывести шаг деинсталляции."""
    print(f'\n[Шаг {step_num}/{total}] {text}')
    print('-' * 80)


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


def check_config_exists():
    """Проверить наличие конфигурационного файла."""
    config_path = 'maintenance-config.json'
    if os.path.exists(config_path):
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
            return config
        except Exception:
            return None
    return None


def remove_task_scheduler():
    """Удалить задачу из планировщика Windows."""
    print_step(1, 5, 'Удаление задачи из планировщика Windows')
    
    task_name = '1C-Sweeper-Maintenance'
    
    try:
        # Проверяем существование задачи
        result = subprocess.run(
            ['schtasks', '/Query', '/TN', task_name],
            capture_output=True,
            text=True,
            encoding='cp1251',
            errors='ignore'
        )
        
        if result.returncode == 0:
            # Задача существует, удаляем её
            delete_result = subprocess.run(
                ['schtasks', '/Delete', '/TN', task_name, '/F'],
                capture_output=True,
                text=True,
                encoding='cp1251',
                errors='ignore'
            )
            
            if delete_result.returncode == 0:
                log_message('OK', f'Задача "{task_name}" удалена из планировщика')
                return True
            else:
                log_message('ОШИБКА', f'Не удалось удалить задачу: {delete_result.stderr}')
                return False
        else:
            log_message('ИНФО', 'Задача не найдена в планировщике')
            return True
            
    except Exception as e:
        log_message('ОШИБКА', f'Ошибка при работе с планировщиком: {e}')
        return False


def remove_configuration():
    """Удалить конфигурационные файлы."""
    print_step(2, 5, 'Удаление конфигурационных файлов')
    
    config_files = [
        'maintenance-config.json',
        'maintenance-config.example.json'
    ]
    
    removed_count = 0
    for config_file in config_files:
        if os.path.exists(config_file):
            try:
                os.remove(config_file)
                log_message('OK', f'Удален файл: {config_file}')
                removed_count += 1
            except Exception as e:
                log_message('ОШИБКА', f'Не удалось удалить {config_file}: {e}')
        else:
            log_message('ИНФО', f'Файл не найден: {config_file}')
    
    if removed_count > 0:
        log_message('OK', f'Удалено конфигурационных файлов: {removed_count}')
    else:
        log_message('ИНФО', 'Конфигурационные файлы не найдены')
    
    return True


def remove_reports_directory(force=False):
    """Удалить директорию с отчетами."""
    print_step(3, 5, 'Удаление директории с отчетами')
    
    # Сначала пытаемся найти путь из конфигурации
    config = check_config_exists()
    reports_path = './reports'  # значение по умолчанию
    
    if config and 'settings' in config and 'general' in config['settings']:
        reports_path = config['settings']['general'].get('reportsPath', './reports')
    
    if os.path.exists(reports_path):
        try:
            # Подсчитываем файлы перед удалением
            report_files = []
            for root, dirs, files in os.walk(reports_path):
                for file in files:
                    if file.endswith('.json'):
                        report_files.append(os.path.join(root, file))
            
            if report_files:
                print(f'[ИНФО] Найдено отчетов: {len(report_files)}')
                print('Примеры файлов отчетов:')
                for i, file in enumerate(report_files[:5]):  # Показываем первые 5
                    print(f'  - {file}')
                if len(report_files) > 5:
                    print(f'  ... и еще {len(report_files) - 5} файлов')
                
                if force or get_yes_no('Удалить все отчеты?', False):
                    shutil.rmtree(reports_path)
                    print(f'[OK] Директория с отчетами удалена: {reports_path}')
                else:
                    print('[ПРОПУЩЕНО] Отчеты сохранены')
            else:
                print('[ИНФО] Отчеты не найдены')
                if force or get_yes_no('Удалить пустую директорию?', True):
                    os.rmdir(reports_path)
                    print(f'[OK] Пустая директория удалена: {reports_path}')
                else:
                    print('[ПРОПУЩЕНО] Директория сохранена')
        except Exception as e:
            print(f'[ОШИБКА] Не удалось удалить директорию отчетов: {e}')
            return False
    else:
        print('[ИНФО] Директория с отчетами не найдена')
    
    return True


def remove_dependencies(force=False):
    """Удалить установленные зависимости."""
    print_step(4, 5, 'Удаление зависимостей')
    
    if not force and not get_yes_no('Удалить установленные Python-пакеты?', False):
        print('[ПРОПУЩЕНО] Зависимости сохранены')
        return True
    
    # Список пакетов для удаления
    packages_to_remove = [
        'psutil',
        'pytest',
        'pytest-cov', 
        'pytest-mock'
    ]
    
    print('Будут удалены следующие пакеты:')
    for package in packages_to_remove:
        print(f'  - {package}')
    
    if not force and not get_yes_no('Продолжить удаление пакетов?', False):
        print('[ПРОПУЩЕНО] Удаление пакетов отменено')
        return True
    
    removed_count = 0
    for package in packages_to_remove:
        try:
            result = subprocess.run(
                [sys.executable, '-m', 'pip', 'uninstall', package, '-y'],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                print(f'[OK] Пакет {package} удален')
                removed_count += 1
            else:
                print(f'[ПРЕДУПРЕЖДЕНИЕ] Не удалось удалить {package}: {result.stderr}')
        except Exception as e:
            print(f'[ОШИБКА] Ошибка при удалении {package}: {e}')
    
    print(f'[OK] Удалено пакетов: {removed_count}/{len(packages_to_remove)}')
    return True


def remove_source_files(force=False):
    """Удалить исходные файлы системы."""
    print_step(5, 5, 'Удаление исходных файлов')
    
    if not force and not get_yes_no('Удалить исходные файлы системы 1C-Sweeper?', False):
        print('[ПРОПУЩЕНО] Исходные файлы сохранены')
        return True
    
    # Файлы и директории для удаления
    items_to_remove = [
        'src/',
        'tests/',
        'docs/',
        'install.py',
        'uninstall.py',
        'requirements.txt',
        'pytest.ini',
        'CONTRIBUTING.md',
        'LICENSE',
        'README.md'
    ]
    
    print('Будут удалены следующие файлы и директории:')
    for item in items_to_remove:
        if os.path.exists(item):
            print(f'  - {item}')
    
    if not force and not get_yes_no('Продолжить удаление исходных файлов?', False):
        print('[ПРОПУЩЕНО] Удаление исходных файлов отменено')
        return True
    
    removed_count = 0
    for item in items_to_remove:
        if os.path.exists(item):
            try:
                if os.path.isdir(item):
                    shutil.rmtree(item)
                else:
                    os.remove(item)
                print(f'[OK] Удален: {item}')
                removed_count += 1
            except Exception as e:
                print(f'[ОШИБКА] Не удалось удалить {item}: {e}')
    
    print(f'[OK] Удалено элементов: {removed_count}')
    return True


def show_summary():
    """Показать сводку деинсталляции."""
    print_header('СВОДКА ДЕИНСТАЛЛЯЦИИ')
    
    print('Выполненные действия:')
    print('+ Удалена задача из планировщика Windows')
    print('+ Удалены конфигурационные файлы')
    print('+ Обработана директория с отчетами')
    print('+ Удалены зависимости (опционально)')
    print('+ Удалены исходные файлы (опционально)')
    print()
    print('Система 1C-Sweeper успешно удалена!')
    print()
    print('Примечания:')
    print('- Если вы удалили зависимости, они могут использоваться другими проектами')
    print('- Отчеты сохранены (если не были удалены) для возможного анализа')
    print('- Для полного удаления также удалите директорию проекта')


def main():
    """Главная функция деинсталляции."""
    parser = argparse.ArgumentParser(
        description='1C-Sweeper Uninstaller: Удаление системы автоматизированного обслуживания',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        '--force', '-f',
        action='store_true',
        help='Принудительное удаление без запросов подтверждения'
    )
    
    parser.add_argument(
        '--keep-reports',
        action='store_true',
        help='Сохранить директорию с отчетами'
    )
    
    parser.add_argument(
        '--keep-dependencies',
        action='store_true',
        help='Сохранить установленные Python-пакеты'
    )
    
    parser.add_argument(
        '--keep-source',
        action='store_true',
        help='Сохранить исходные файлы системы'
    )
    
    args = parser.parse_args()
    
    print_header('ДЕИНСТАЛЛЯТОР 1C-SWEEPER')
    print('Система автоматизированного обслуживания Git-репозиториев,')
    print('EDT workspaces и информационных баз 1С')
    print()
    print('Этот скрипт удалит:')
    print('- Задачу из планировщика Windows')
    print('- Конфигурационные файлы')
    print('- Директорию с отчетами (опционально)')
    print('- Установленные зависимости (опционально)')
    print('- Исходные файлы системы (опционально)')
    print()
    
    if not args.force:
        if not get_yes_no('Продолжить деинсталляцию?', False):
            print('[ОТМЕНЕНО] Деинсталляция отменена пользователем')
            return
    
    # Проверяем наличие конфигурации
    config = check_config_exists()
    if not config:
        print('[ПРЕДУПРЕЖДЕНИЕ] Конфигурационный файл не найден')
        print('[ИНФО] Возможно, система уже была удалена или не была установлена')
        
        if not args.force:
            if not get_yes_no('Продолжить деинсталляцию?', False):
                print('[ОТМЕНЕНО] Деинсталляция отменена')
                return
    
    # Выполняем шаги деинсталляции
    success_count = 0
    total_steps = 5
    
    if remove_task_scheduler():
        success_count += 1
    
    if remove_configuration():
        success_count += 1
    
    if args.keep_reports:
        print('[ПРОПУЩЕНО] Сохранение отчетов (--keep-reports)')
        success_count += 1
    else:
        if remove_reports_directory(args.force):
            success_count += 1
    
    if args.keep_dependencies:
        print('[ПРОПУЩЕНО] Сохранение зависимостей (--keep-dependencies)')
        success_count += 1
    else:
        if remove_dependencies(args.force):
            success_count += 1
    
    if args.keep_source:
        print('[ПРОПУЩЕНО] Сохранение исходных файлов (--keep-source)')
        success_count += 1
    else:
        if remove_source_files(args.force):
            success_count += 1
    
    # Показываем результат
    print_header('ДЕИНСТАЛЛЯЦИЯ ЗАВЕРШЕНА')
    
    if success_count == total_steps:
        print('[OK] Все шаги деинсталляции выполнены успешно')
    else:
        print(f'[ПРЕДУПРЕЖДЕНИЕ] Выполнено {success_count}/{total_steps} шагов')
        print('[ИНФО] Некоторые операции могли быть пропущены или завершились с ошибками')
    
    show_summary()


if __name__ == '__main__':
    main()

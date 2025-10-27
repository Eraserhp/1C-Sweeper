"""
Основной модуль системы автоматизированного обслуживания.
Объединяет все обработчики и управляет процессом обслуживания.
"""

import json
import sys
import argparse
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional

from .git_handler import GitHandler
from .edt_handler import EdtHandler
from .db_handler import DatabaseHandler
from .reporter import Reporter
from .utils import format_log_message


class MaintenanceSystem:
    """Основная система обслуживания."""
    
    def __init__(self, config_path: str = 'maintenance-config.json', silent: bool = False):
        """
        Инициализация системы.
        
        Args:
            config_path: Путь к конфигурационному файлу
            silent: Тихий режим работы
        """
        self.config_path = config_path
        self.silent = silent
        self.config = None
    
    def load_config(self) -> bool:
        """
        Загрузить конфигурацию из файла.
        
        Returns:
            True если конфигурация загружена успешно, False иначе
        """
        try:
            with open(self.config_path, 'r', encoding='utf-8') as f:
                self.config = json.load(f)
            return True
        except FileNotFoundError:
            self.log_error(f'Configuration file not found: {self.config_path}')
            return False
        except json.JSONDecodeError as e:
            self.log_error(f'Invalid JSON in configuration file: {e}')
            return False
        except Exception as e:
            self.log_error(f'Error loading configuration: {e}')
            return False
    
    def validate_config(self) -> bool:
        """
        Валидировать конфигурацию.
        
        Returns:
            True если конфигурация валидна, False иначе
        """
        if not self.config:
            return False
        
        # Проверяем наличие обязательной структуры
        if 'settings' not in self.config:
            self.log_error('Missing "settings" section in configuration')
            return False
        
        settings = self.config['settings']
        
        # Проверяем наличие хотя бы одной секции обработчиков
        has_git = 'git' in settings
        has_edt = 'edt' in settings
        has_db = 'database' in settings
        
        if not (has_git or has_edt or has_db):
            self.log_error('Configuration must have at least one handler section (git, edt, database)')
            return False
        
        return True
    
    def log_info(self, message: str):
        """Вывести информационное сообщение."""
        if not self.silent:
            print(format_log_message('INFO', message))
    
    def log_success(self, message: str):
        """Вывести сообщение об успехе."""
        if not self.silent:
            print(format_log_message('SUCCESS', message))
    
    def log_warning(self, message: str):
        """Вывести предупреждение."""
        if not self.silent:
            print(format_log_message('WARNING', message))
    
    def log_error(self, message: str):
        """Вывести сообщение об ошибке (даже в тихом режиме)."""
        print(format_log_message('ERROR', message), file=sys.stderr)
    
    def run(self) -> int:
        """
        Запустить процесс обслуживания.
        
        Returns:
            Код возврата: 0 = успех, 1 = ошибки
        """
        start_time = datetime.now()
        
        self.log_info(f'Starting maintenance at {start_time.strftime("%Y-%m-%d %H:%M:%S")}')
        
        # Загружаем и валидируем конфигурацию
        if not self.load_config():
            return 1
        
        if not self.validate_config():
            return 1
        
        settings = self.config['settings']
        general_settings = settings.get('general', {})
        
        # Проверяем режим работы из конфигурации
        if general_settings.get('silentMode', False):
            self.silent = True
        
        # Инициализируем результаты
        git_results = []
        edt_results = []
        db_results = []
        
        # Отслеживаем какие секции были обработаны
        processed_sections = {
            'git': False,
            'edt': False,
            'database': False
        }
        
        has_errors = False
        
        # Обрабатываем Git-репозитории
        if 'git' in settings:
            processed_sections['git'] = True
            self.log_info('=== Processing Git repositories ===')
            try:
                git_handler = GitHandler(settings['git'], self.silent)
                git_results = git_handler.process_all()
                
                # Проверяем наличие ошибок
                for result in git_results:
                    if result.get('status') == 'error':
                        has_errors = True
            except Exception as e:
                self.log_error(f'Git handler error: {e}')
                has_errors = True
        
        # Обрабатываем EDT workspaces
        if 'edt' in settings:
            processed_sections['edt'] = True
            self.log_info('=== Processing EDT workspaces ===')
            try:
                edt_handler = EdtHandler(settings['edt'], self.silent)
                edt_results = edt_handler.process_all()
                
                # Проверяем наличие ошибок
                for result in edt_results:
                    if result.get('status') == 'error':
                        has_errors = True
            except Exception as e:
                self.log_error(f'EDT handler error: {e}')
                has_errors = True
        
        # Обрабатываем базы 1С
        db_handler = None
        if 'database' in settings:
            processed_sections['database'] = True
            self.log_info('=== Processing 1C databases ===')
            try:
                db_handler = DatabaseHandler(settings['database'], self.silent)
                db_results = db_handler.process_all()
                
                # Проверяем наличие ошибок
                for result in db_results:
                    if result.get('status') == 'error':
                        has_errors = True
            except Exception as e:
                self.log_error(f'Database handler error: {e}')
                has_errors = True
        
        # Формируем отчет
        end_time = datetime.now()
        
        reports_path = general_settings.get('reportsPath', './reports')
        reporter = Reporter(reports_path)
        
        report = reporter.generate_report(
            git_results,
            edt_results,
            db_results,
            start_time,
            end_time,
            processed_sections
        )
        
        # Сохраняем отчет
        try:
            report_file = reporter.save_report(report)
            self.log_success(f'Report saved to: {report_file}')
        except Exception as e:
            self.log_error(f'Failed to save report: {e}')
            has_errors = True
        
        # Выводим сводку
        reporter.print_summary(report, self.silent)
        
        # Итоговое сообщение
        duration = (end_time - start_time).total_seconds()
        self.log_info(f'Maintenance completed in {int(duration)} seconds')
        
        if has_errors:
            self.log_warning('Maintenance completed with errors')
            return 1
        else:
            self.log_success('Maintenance completed successfully')
            return 0


def main():
    """Точка входа в программу."""
    parser = argparse.ArgumentParser(
        description='1C-Sweeper: Система автоматизированного обслуживания',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        '-c', '--config',
        default='maintenance-config.json',
        help='Path to configuration file (default: maintenance-config.json)'
    )
    
    parser.add_argument(
        '-s', '--silent',
        action='store_true',
        help='Silent mode: only critical errors to console'
    )
    
    args = parser.parse_args()
    
    # Запускаем систему
    system = MaintenanceSystem(config_path=args.config, silent=args.silent)
    exit_code = system.run()
    
    sys.exit(exit_code)


if __name__ == '__main__':
    main()


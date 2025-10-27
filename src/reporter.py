"""
Формирование JSON-отчетов о выполненных операциях обслуживания.
"""

import json
import os
import socket
from datetime import datetime
from typing import Dict, List
from .utils import ensure_dir


class Reporter:
    """Класс для формирования отчетов."""
    
    def __init__(self, reports_path: str = './reports'):
        """
        Инициализация генератора отчетов.
        
        Args:
            reports_path: Путь для сохранения отчетов
        """
        self.reports_path = reports_path
        ensure_dir(reports_path)
    
    def generate_report(
        self,
        git_results: List[Dict],
        edt_results: List[Dict],
        db_results: List[Dict],
        start_time: datetime,
        end_time: datetime,
        processed_sections: Dict[str, bool] = None
    ) -> Dict:
        """
        Сгенерировать отчет о выполненных операциях.
        
        Args:
            git_results: Результаты обработки Git-репозиториев
            edt_results: Результаты обработки EDT workspaces
            db_results: Результаты обработки баз 1С
            start_time: Время начала обслуживания
            end_time: Время окончания обслуживания
            
        Returns:
            Структура отчета
        """
        duration = int((end_time - start_time).total_seconds())
        
        # Подсчитываем общую статистику
        total_space_saved = 0.0
        git_success = 0
        git_failed = 0
        edt_success = 0
        edt_failed = 0
        db_success = 0
        db_failed = 0
        
        errors = []
        
        # Обрабатываем результаты Git
        for result in git_results:
            total_space_saved += result.get('spaceSaved', 0.0)
            if result.get('status') == 'success':
                git_success += 1
            elif result.get('status') == 'error':
                git_failed += 1
                if result.get('errors'):
                    errors.append({
                        'type': 'git',
                        'path': result.get('path'),
                        'errors': result['errors']
                    })
        
        # Обрабатываем результаты EDT
        for result in edt_results:
            total_space_saved += result.get('spaceSaved', 0.0)
            if result.get('status') == 'success':
                edt_success += 1
            elif result.get('status') == 'error':
                edt_failed += 1
                if result.get('errors'):
                    errors.append({
                        'type': 'edt',
                        'path': result.get('path'),
                        'errors': result['errors']
                    })
        
        # Обрабатываем результаты баз 1С
        for result in db_results:
            total_space_saved += result.get('spaceSaved', 0.0)
            if result.get('status') == 'success':
                db_success += 1
            elif result.get('status') == 'error':
                db_failed += 1
                if result.get('errors'):
                    errors.append({
                        'type': 'database',
                        'path': result.get('path'),
                        'errors': result['errors']
                    })
        
        # Формируем отчет
        report = {
            'reportVersion': '1.0',
            'timestamp': start_time.isoformat(),
            'duration': duration,
            'hostname': socket.gethostname(),
            'summary': {
                'totalSpaceSaved': round(total_space_saved, 2),
                'gitReposProcessed': len(git_results),
                'gitReposSuccess': git_success,
                'gitReposFailed': git_failed,
                'workspacesProcessed': len(edt_results),
                'workspacesSuccess': edt_success,
                'workspacesFailed': edt_failed,
                'databasesProcessed': len(db_results),
                'databasesSuccess': db_success,
                'databasesFailed': db_failed,
            },
            'errors': errors
        }
        
        # Добавляем секции только если они были обработаны
        if processed_sections and processed_sections.get('git', False):
            report['gitRepositories'] = git_results
        if processed_sections and processed_sections.get('edt', False):
            report['edtWorkspaces'] = edt_results
        if processed_sections and processed_sections.get('database', False):
            report['databases'] = db_results
        
        return report
    
    def save_report(self, report: Dict) -> str:
        """
        Сохранить отчет в файл.
        
        Args:
            report: Структура отчета
            
        Returns:
            Путь к сохраненному файлу
        """
        # Формируем имя файла
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f'report_{timestamp}.json'
        filepath = os.path.join(self.reports_path, filename)
        
        # Сохраняем отчет
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        
        return filepath
    
    def print_summary(self, report: Dict, silent: bool = False):
        """
        Вывести краткую сводку отчета в консоль.
        
        Args:
            report: Структура отчета
            silent: Тихий режим (не выводить в консоль)
        """
        if silent:
            return
        
        summary = report['summary']
        
        print('\n' + '=' * 80)
        print('СВОДКА ОБСЛУЖИВАНИЯ')
        print('=' * 80)
        print(f'Время выполнения: {report["duration"]} секунд')
        print(f'Всего освобождено: {summary["totalSpaceSaved"]} ГБ')
        print()
        
        # Git-репозитории - показываем всегда если есть конфигурация
        if 'gitRepositories' in report:
            if summary['gitReposProcessed'] > 0:
                print(f'Git-репозитории:')
                print(f'  Обработано: {summary["gitReposProcessed"]}')
                print(f'  Успешно: {summary["gitReposSuccess"]}')
                print(f'  Ошибок: {summary["gitReposFailed"]}')
                print()
            else:
                print(f'Git-репозитории:')
                print(f'  Найдено: 0')
                print(f'  Причина: Репозитории не найдены в указанных путях')
                print()
        
        # EDT workspaces - показываем всегда если есть конфигурация
        if 'edtWorkspaces' in report:
            if summary['workspacesProcessed'] > 0:
                print(f'EDT workspaces:')
                print(f'  Обработано: {summary["workspacesProcessed"]}')
                print(f'  Успешно: {summary["workspacesSuccess"]}')
                print(f'  Ошибок: {summary["workspacesFailed"]}')
                print()
            else:
                print(f'EDT workspaces:')
                print(f'  Найдено: 0')
                print(f'  Причина: Workspaces не найдены в указанных путях')
                print()
        
        # Базы 1С - показываем всегда если есть конфигурация
        if 'databases' in report:
            if summary['databasesProcessed'] > 0:
                print(f'Базы данных 1С:')
                print(f'  Обработано: {summary["databasesProcessed"]}')
                print(f'  Успешно: {summary["databasesSuccess"]}')
                print(f'  Ошибок: {summary["databasesFailed"]}')
                print()
            else:
                print(f'Базы данных 1С:')
                print(f'  Найдено: 0')
                print(f'  Причина: Базы данных не найдены в указанных путях')
                print()
        
        # Ошибки
        if report['errors']:
            print(f'ОШИБКИ ({len(report["errors"])}):')
            for error in report['errors']:
                print(f'  [{error["type"].upper()}] {error["path"]}')
                for err_msg in error['errors']:
                    print(f'    - {err_msg}')
            print()
        
        print('=' * 80)


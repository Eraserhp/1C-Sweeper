"""
Обработчик EDT workspaces: безопасная очистка временных файлов и кэшей.
"""

import os
import glob
from typing import Dict, List
from .utils import get_size_gb, is_process_running, safe_remove_file, safe_remove_dir


class EdtHandler:
    """Класс для обслуживания EDT workspaces."""
    
    # White-list безопасных для удаления путей
    SAFE_TO_DELETE = {
        'logs': [
            '.metadata/.log',
            '.metadata/.bak_*.log',
        ],
        'history': [
            '.metadata/.plugins/org.eclipse.core.resources/.history',
        ],
        'snapshots': [
            '.metadata/.plugins/org.eclipse.core.resources/.snap',
            '.metadata/.plugins/*/snapshots',
        ],
        'caches': [
            '.metadata/.plugins/org.eclipse.pde.core/.bundle_pool',
            '.metadata/.plugins/org.eclipse.e4.workbench/workbench.xmi.bak',
            '.metadata/.plugins/org.eclipse.core.resources/.safetable',
            '.metadata/.plugins/org.eclipse.jdt.core/*.index',
        ],
    }
    
    def __init__(self, config: dict, silent: bool = False):
        """
        Инициализация обработчика.
        
        Args:
            config: Конфигурация EDT (workspaces, searchPaths, sizeThresholdGB)
            silent: Тихий режим работы
        """
        self.config = config
        self.silent = silent
        self.results = []
    
    def find_workspaces(self) -> List[str]:
        """
        Найти все workspaces для обработки.
        
        Returns:
            Список путей к workspaces
        """
        from .utils import find_edt_workspaces
        
        workspaces = set()
        
        # Добавляем явно указанные workspaces
        explicit_workspaces = self.config.get('workspaces', [])
        for ws in explicit_workspaces:
            if os.path.isdir(os.path.join(ws, '.metadata')):
                workspaces.add(os.path.abspath(ws))
        
        # Ищем workspaces в searchPaths
        search_paths = self.config.get('searchPaths', [])
        found_workspaces = find_edt_workspaces(search_paths)
        workspaces.update(found_workspaces)
        
        return sorted(list(workspaces))
    
    def is_workspace_locked(self, workspace_path: str) -> bool:
        """
        Проверить, заблокирован ли workspace (открыт в EDT).
        
        Args:
            workspace_path: Путь к workspace
            
        Returns:
            True если workspace открыт в EDT, False иначе
        """
        # Проверяем файл блокировки
        lock_file = os.path.join(workspace_path, '.metadata', '.lock')
        if os.path.exists(lock_file):
            return True
        
        # Проверяем запущенные процессы EDT
        if is_process_running(['1cedt.exe', 'eclipse.exe']):
            # EDT запущен, но возможно это другой workspace
            # Для безопасности считаем workspace заблокированным
            return True
        
        return False
    
    def clean_workspace(self, workspace_path: str) -> Dict:
        """
        Очистить workspace от временных файлов.
        
        Args:
            workspace_path: Путь к workspace
            
        Returns:
            Статистика удаления по категориям
        """
        stats = {
            'logsCleared': 0,
            'historyCleared': 0,
            'snapshotsCleared': 0,
            'cachesCleared': 0,
        }
        
        # Удаляем логи
        for pattern in self.SAFE_TO_DELETE['logs']:
            full_pattern = os.path.join(workspace_path, pattern)
            
            # Обрабатываем паттерны с wildcard
            if '*' in pattern:
                for filepath in glob.glob(full_pattern):
                    if os.path.isfile(filepath):
                        if safe_remove_file(filepath):
                            stats['logsCleared'] += 1
            else:
                # Точный путь к файлу
                if os.path.exists(full_pattern):
                    if safe_remove_file(full_pattern):
                        stats['logsCleared'] += 1
        
        # Также удаляем все *.log в plugins
        plugins_dir = os.path.join(workspace_path, '.metadata', '.plugins')
        if os.path.isdir(plugins_dir):
            for root, dirs, files in os.walk(plugins_dir):
                for file in files:
                    if file.endswith('.log'):
                        filepath = os.path.join(root, file)
                        if safe_remove_file(filepath):
                            stats['logsCleared'] += 1
        
        # Удаляем историю
        for pattern in self.SAFE_TO_DELETE['history']:
            full_path = os.path.join(workspace_path, pattern)
            if os.path.isdir(full_path):
                # Подсчитываем файлы перед удалением
                file_count = sum(1 for _, _, files in os.walk(full_path) for _ in files)
                if safe_remove_dir(full_path):
                    stats['historyCleared'] += file_count
        
        # Удаляем снапшоты
        for pattern in self.SAFE_TO_DELETE['snapshots']:
            if '*' in pattern:
                # Паттерн с wildcard
                base_path = os.path.join(workspace_path, pattern.split('*')[0])
                suffix = pattern.split('*')[-1] if len(pattern.split('*')) > 1 else ''
                
                # Ищем все подходящие папки
                metadata_plugins = os.path.join(workspace_path, '.metadata', '.plugins')
                if os.path.isdir(metadata_plugins):
                    for plugin_dir in os.listdir(metadata_plugins):
                        snapshot_dir = os.path.join(metadata_plugins, plugin_dir, suffix.lstrip('/'))
                        if os.path.isdir(snapshot_dir):
                            file_count = sum(1 for _, _, files in os.walk(snapshot_dir) for _ in files)
                            if safe_remove_dir(snapshot_dir):
                                stats['snapshotsCleared'] += file_count
            else:
                full_path = os.path.join(workspace_path, pattern)
                if os.path.isfile(full_path):
                    if safe_remove_file(full_path):
                        stats['snapshotsCleared'] += 1
                elif os.path.isdir(full_path):
                    file_count = sum(1 for _, _, files in os.walk(full_path) for _ in files)
                    if safe_remove_dir(full_path):
                        stats['snapshotsCleared'] += file_count
        
        # Удаляем кэши
        for pattern in self.SAFE_TO_DELETE['caches']:
            full_pattern = os.path.join(workspace_path, pattern)
            
            if '*' in pattern:
                for path in glob.glob(full_pattern):
                    if os.path.isfile(path):
                        if safe_remove_file(path):
                            stats['cachesCleared'] += 1
                    elif os.path.isdir(path):
                        file_count = sum(1 for _, _, files in os.walk(path) for _ in files)
                        if safe_remove_dir(path):
                            stats['cachesCleared'] += file_count
            else:
                if os.path.isfile(full_pattern):
                    if safe_remove_file(full_pattern):
                        stats['cachesCleared'] += 1
                elif os.path.isdir(full_pattern):
                    file_count = sum(1 for _, _, files in os.walk(full_pattern) for _ in files)
                    if safe_remove_dir(full_pattern):
                        stats['cachesCleared'] += file_count
        
        return stats
    
    def process_workspace(self, workspace_path: str) -> Dict:
        """
        Обработать один workspace.
        
        Args:
            workspace_path: Путь к workspace
            
        Returns:
            Результат обработки
        """
        result = {
            'path': workspace_path,
            'sizeBefore': 0.0,
            'sizeAfter': 0.0,
            'spaceSaved': 0.0,
            'filesDeleted': 0,
            'duration': 0,
            'actions': [],
            'details': {
                'logsCleared': 0,
                'historyCleared': 0,
                'snapshotsCleared': 0,
                'cachesCleared': 0,
            },
            'status': 'pending',
            'errors': []
        }
        
        import time
        start_time = time.time()
        
        try:
            # Проверяем существование workspace
            metadata_dir = os.path.join(workspace_path, '.metadata')
            if not os.path.isdir(metadata_dir):
                result['status'] = 'error'
                result['errors'].append('Not an EDT workspace (no .metadata directory)')
                return result
            
            # Получаем размер до обработки
            result['sizeBefore'] = get_size_gb(workspace_path)
            
            # Проверяем порог размера
            threshold = self.config.get('sizeThresholdGB', 5)
            if result['sizeBefore'] < threshold:
                result['status'] = 'skipped'
                result['errors'].append(f'Size {result["sizeBefore"]} GB below threshold {threshold} GB')
                return result
            
            # Проверяем блокировку
            if self.is_workspace_locked(workspace_path):
                result['status'] = 'error'
                result['errors'].append('Workspace is locked (EDT is running)')
                return result
            
            # Выполняем очистку
            stats = self.clean_workspace(workspace_path)
            result['details'] = stats
            result['filesDeleted'] = sum(stats.values())
            
            # Формируем список действий
            if stats['logsCleared'] > 0:
                result['actions'].append('clear_logs')
            if stats['historyCleared'] > 0:
                result['actions'].append('clear_history')
            if stats['snapshotsCleared'] > 0:
                result['actions'].append('clear_snapshots')
            if stats['cachesCleared'] > 0:
                result['actions'].append('clear_caches')
            
            # Получаем размер после обработки
            result['sizeAfter'] = get_size_gb(workspace_path)
            result['spaceSaved'] = round(result['sizeBefore'] - result['sizeAfter'], 2)
            
            result['status'] = 'success'
            
        except Exception as e:
            result['status'] = 'error'
            result['errors'].append(f'Unexpected error: {str(e)}')
        finally:
            result['duration'] = int(time.time() - start_time)
        
        return result
    
    def process_all(self) -> List[Dict]:
        """
        Обработать все workspaces.
        
        Returns:
            Список результатов обработки
        """
        workspaces = self.find_workspaces()
        
        if not workspaces:
            if not self.silent:
                print('[INFO] No EDT workspaces found')
            return []
        
        if not self.silent:
            print(f'[INFO] Found {len(workspaces)} EDT workspaces')
        
        results = []
        for i, workspace in enumerate(workspaces, 1):
            if not self.silent:
                print(f'[INFO] Processing workspace {i}/{len(workspaces)}: {workspace}')
            
            result = self.process_workspace(workspace)
            results.append(result)
            
            if not self.silent:
                if result['status'] == 'success':
                    print(f'[SUCCESS] Space saved: {result["spaceSaved"]} GB, files deleted: {result["filesDeleted"]}')
                elif result['status'] == 'skipped':
                    print(f'[INFO] Skipped: {result["errors"][0]}')
                else:
                    print(f'[ERROR] Failed: {", ".join(result["errors"])}')
        
        self.results = results
        return results


"""
Обработчик Git-репозиториев: диагностика, очистка garbage, сборка мусора.
"""

import os
import re
import subprocess
from typing import Dict, List, Optional
from .utils import get_size_gb, is_path_locked


class GitHandler:
    """Класс для обслуживания Git-репозиториев."""
    
    def __init__(self, config: dict, silent: bool = False):
        """
        Инициализация обработчика.
        
        Args:
            config: Конфигурация Git (repos, searchPaths, sizeThresholdGB)
            silent: Тихий режим работы
        """
        self.config = config
        self.silent = silent
        self.results = []
    
    def check_git_available(self) -> bool:
        """
        Проверить доступность Git в системе.
        
        Returns:
            True если Git доступен, False иначе
        """
        try:
            subprocess.run(
                ['git', '--version'],
                capture_output=True,
                check=True,
                timeout=10
            )
            return True
        except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
            return False
    
    def find_repositories(self) -> List[str]:
        """
        Найти все репозитории для обработки.
        
        Returns:
            Список путей к репозиториям
        """
        from .utils import find_git_repos
        
        repos = set()
        
        # Добавляем явно указанные репозитории
        explicit_repos = self.config.get('repos', [])
        for repo in explicit_repos:
            if os.path.isdir(os.path.join(repo, '.git')):
                repos.add(os.path.abspath(repo))
        
        # Ищем репозитории в searchPaths
        search_paths = self.config.get('searchPaths', [])
        found_repos = find_git_repos(search_paths)
        repos.update(found_repos)
        
        return sorted(list(repos))
    
    def get_garbage_info(self, repo_path: str) -> Dict:
        """
        Получить информацию о garbage в репозитории.
        
        Args:
            repo_path: Путь к репозиторию
            
        Returns:
            Словарь с информацией о garbage
        """
        result = {
            'size_gb': 0.0,
            'pack_files_without_idx': []
        }
        
        try:
            # Выполняем git count-objects -v
            output = subprocess.run(
                ['git', 'count-objects', '-v'],
                cwd=repo_path,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if output.returncode == 0:
                # Ищем строку "size-garbage: N"
                for line in output.stdout.splitlines():
                    if line.startswith('size-garbage:'):
                        # Размер в килобайтах
                        size_kb = int(line.split(':')[1].strip())
                        result['size_gb'] = round(size_kb / (1024 * 1024), 2)
                        break
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, ValueError):
            pass
        
        # Ищем pack-файлы без .idx
        pack_dir = os.path.join(repo_path, '.git', 'objects', 'pack')
        if os.path.isdir(pack_dir):
            try:
                pack_files = [f for f in os.listdir(pack_dir) if f.endswith('.pack')]
                for pack_file in pack_files:
                    idx_file = pack_file[:-5] + '.idx'  # заменяем .pack на .idx
                    if idx_file not in os.listdir(pack_dir):
                        pack_path = os.path.join(pack_dir, pack_file)
                        pack_size = os.path.getsize(pack_path) / (1024 ** 3)  # в ГБ
                        result['pack_files_without_idx'].append({
                            'name': pack_file,
                            'size_gb': round(pack_size, 2)
                        })
            except (OSError, PermissionError):
                pass
        
        return result
    
    def remove_garbage_packs(self, repo_path: str) -> int:
        """
        Удалить некомплектные pack-файлы (без .idx).
        
        Args:
            repo_path: Путь к репозиторию
            
        Returns:
            Количество удаленных pack-файлов
        """
        removed_count = 0
        pack_dir = os.path.join(repo_path, '.git', 'objects', 'pack')
        
        if not os.path.isdir(pack_dir):
            return 0
        
        try:
            pack_files = [f for f in os.listdir(pack_dir) if f.endswith('.pack')]
            
            for pack_file in pack_files:
                idx_file = pack_file[:-5] + '.idx'
                
                # Если нет соответствующего .idx файла - удаляем
                if idx_file not in os.listdir(pack_dir):
                    pack_path = os.path.join(pack_dir, pack_file)
                    try:
                        os.remove(pack_path)
                        removed_count += 1
                        
                        # Также удаляем связанный .mtimes файл если есть
                        mtimes_file = pack_file[:-5] + '.mtimes'
                        mtimes_path = os.path.join(pack_dir, mtimes_file)
                        if os.path.exists(mtimes_path):
                            os.remove(mtimes_path)
                    except (OSError, PermissionError):
                        continue
        except (OSError, PermissionError):
            pass
        
        return removed_count
    
    def process_repository(self, repo_path: str) -> Dict:
        """
        Обработать один репозиторий.
        
        Args:
            repo_path: Путь к репозиторию
            
        Returns:
            Результат обработки
        """
        result = {
            'path': repo_path,
            'sizeBefore': 0.0,
            'sizeAfter': 0.0,
            'spaceSaved': 0.0,
            'garbageBefore': 0.0,
            'garbageAfter': 0.0,
            'garbagePacksRemoved': 0,
            'duration': 0,
            'actions': [],
            'status': 'pending',
            'errors': []
        }
        
        import time
        start_time = time.time()
        
        try:
            # Проверяем существование репозитория
            if not os.path.isdir(os.path.join(repo_path, '.git')):
                result['status'] = 'error'
                result['errors'].append('Not a Git repository')
                return result
            
            # Получаем размер до обработки
            result['sizeBefore'] = get_size_gb(repo_path)
            
            # Проверяем порог размера
            threshold = self.config.get('sizeThresholdGB', 15)
            if result['sizeBefore'] < threshold:
                result['status'] = 'skipped'
                result['errors'].append(f'Size {result["sizeBefore"]} GB below threshold {threshold} GB')
                return result
            
            # Проверяем блокировку
            git_dir = os.path.join(repo_path, '.git')
            if is_path_locked(git_dir):
                result['status'] = 'error'
                result['errors'].append('Repository is locked by another process')
                return result
            
            # Получаем информацию о garbage
            garbage_info = self.get_garbage_info(repo_path)
            result['garbageBefore'] = garbage_info['size_gb']
            
            # Удаляем некомплектные pack-файлы если есть
            if garbage_info['pack_files_without_idx']:
                removed = self.remove_garbage_packs(repo_path)
                result['garbagePacksRemoved'] = removed
                if removed > 0:
                    result['actions'].append('remove_garbage_packs')
            
            # Выполняем git remote prune origin
            try:
                subprocess.run(
                    ['git', 'remote', 'prune', 'origin'],
                    cwd=repo_path,
                    capture_output=True,
                    timeout=300,
                    check=True
                )
                result['actions'].append('remote_prune')
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                result['errors'].append(f'Remote prune failed: {str(e)}')
            
            # Выполняем git gc --prune=now
            try:
                subprocess.run(
                    ['git', 'gc', '--prune=now'],
                    cwd=repo_path,
                    capture_output=True,
                    timeout=900,  # 15 минут
                    check=True
                )
                result['actions'].append('gc')
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                result['errors'].append(f'Git gc failed: {str(e)}')
                result['status'] = 'error'
                return result
            
            # Получаем информацию о garbage после очистки
            garbage_info_after = self.get_garbage_info(repo_path)
            result['garbageAfter'] = garbage_info_after['size_gb']
            
            # Получаем размер после обработки
            result['sizeAfter'] = get_size_gb(repo_path)
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
        Обработать все репозитории.
        
        Returns:
            Список результатов обработки
        """
        if not self.check_git_available():
            if not self.silent:
                print('[ERROR] Git is not available in the system')
            return []
        
        repositories = self.find_repositories()
        
        if not repositories:
            if not self.silent:
                print('[INFO] No Git repositories found')
            return []
        
        if not self.silent:
            print(f'[INFO] Found {len(repositories)} Git repositories')
        
        results = []
        for i, repo in enumerate(repositories, 1):
            if not self.silent:
                print(f'[INFO] Processing repository {i}/{len(repositories)}: {repo}')
            
            result = self.process_repository(repo)
            results.append(result)
            
            if not self.silent:
                if result['status'] == 'success':
                    print(f'[SUCCESS] Space saved: {result["spaceSaved"]} GB')
                elif result['status'] == 'skipped':
                    print(f'[INFO] Skipped: {result["errors"][0]}')
                else:
                    print(f'[ERROR] Failed: {", ".join(result["errors"])}')
        
        self.results = results
        return results


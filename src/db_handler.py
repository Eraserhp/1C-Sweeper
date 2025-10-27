"""
Обработчик информационных баз 1С: тестирование и исправление.
"""

import os
import base64
import subprocess
from typing import Dict, List, Optional, Tuple
from .utils import get_size_gb, find_1c_platform, is_path_locked


class DatabaseHandler:
    """Класс для обслуживания информационных баз 1С."""
    
    def __init__(self, config: dict, silent: bool = False):
        """
        Инициализация обработчика.
        
        Args:
            config: Конфигурация баз 1С (databases, searchPaths, platformVersion, etc.)
            silent: Тихий режим работы
        """
        self.config = config
        self.silent = silent
        self.results = []
        self.platform_path = None
        self.platform_version = None
    
    def find_platform(self) -> bool:
        """
        Найти платформу 1С.
        
        Returns:
            True если платформа найдена, False иначе
        """
        version_mask = self.config.get('platformVersion')
        platform_info = find_1c_platform(version_mask)
        
        if platform_info:
            self.platform_path, self.platform_version = platform_info
            return True
        
        return False
    
    def find_databases(self) -> List[str]:
        """
        Найти все базы данных для обработки.
        
        Returns:
            Список путей к базам данных
        """
        from .utils import find_1c_databases
        
        databases = set()
        
        # Добавляем явно указанные базы
        explicit_databases = self.config.get('databases', [])
        for db in explicit_databases:
            if os.path.isfile(db) and db.lower().endswith('.1cd'):
                databases.add(os.path.abspath(db))
        
        # Ищем базы в searchPaths
        search_paths = self.config.get('searchPaths', [])
        found_databases = find_1c_databases(search_paths)
        databases.update(found_databases)
        
        return sorted(list(databases))
    
    def is_database_locked(self, db_path: str) -> bool:
        """
        Проверить, используется ли база данных.
        
        Args:
            db_path: Путь к файлу базы данных
            
        Returns:
            True если база используется, False иначе
        """
        return is_path_locked(db_path)
    
    def get_auth_params(self) -> Tuple[Optional[str], Optional[str]]:
        """
        Получить параметры аутентификации из конфигурации.
        
        Returns:
            Кортеж (username, password) или (None, None)
        """
        username = self.config.get('user')
        password_b64 = self.config.get('password')
        
        if not username:
            return None, None
        
        password = None
        if password_b64:
            try:
                password = base64.b64decode(password_b64).decode('utf-8')
            except Exception:
                password = None
        
        return username, password
    
    def test_and_repair(self, db_path: str) -> Dict:
        """
        Выполнить тестирование и исправление базы данных.
        
        Args:
            db_path: Путь к базе данных
            
        Returns:
            Результат выполнения
        """
        if not self.platform_path:
            return {
                'success': False,
                'error': 'Platform not found'
            }
        
        # Формируем команду
        cmd = [
            self.platform_path,
            'DESIGNER',
            '/F', db_path,
            '/TestAndRepair'
        ]
        
        # Добавляем аутентификацию если есть
        username, password = self.get_auth_params()
        if username:
            cmd.extend(['/N', username])
            if password:
                cmd.extend(['/P', password])
        
        try:
            # Запускаем процесс
            process = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=1800,  # 30 минут максимум
                encoding='cp866'  # Кодировка для вывода 1С
            )
            
            # Код возврата 0 означает успех
            if process.returncode == 0:
                return {
                    'success': True,
                    'error': None
                }
            else:
                # Пытаемся извлечь ошибку из вывода
                error_msg = process.stderr if process.stderr else 'Unknown error'
                return {
                    'success': False,
                    'error': f'Return code {process.returncode}: {error_msg}'
                }
        
        except subprocess.TimeoutExpired:
            return {
                'success': False,
                'error': 'Operation timeout (30 minutes)'
            }
        except Exception as e:
            return {
                'success': False,
                'error': f'Unexpected error: {str(e)}'
            }
    
    def process_database(self, db_path: str) -> Dict:
        """
        Обработать одну базу данных.
        
        Args:
            db_path: Путь к базе данных
            
        Returns:
            Результат обработки
        """
        result = {
            'path': db_path,
            'sizeBefore': 0.0,
            'sizeAfter': 0.0,
            'spaceSaved': 0.0,
            'duration': 0,
            'platform': self.platform_version or 'unknown',
            'actions': [],
            'status': 'pending',
            'errors': []
        }
        
        import time
        start_time = time.time()
        
        try:
            # Проверяем существование базы
            if not os.path.isfile(db_path):
                result['status'] = 'error'
                result['errors'].append('Database file not found')
                return result
            
            # Получаем размер до обработки
            result['sizeBefore'] = get_size_gb(db_path)
            
            # Проверяем порог размера
            threshold = self.config.get('sizeThresholdGB', 3)
            if result['sizeBefore'] < threshold:
                result['status'] = 'skipped'
                result['errors'].append(f'Size {result["sizeBefore"]} GB below threshold {threshold} GB')
                return result
            
            # Проверяем блокировку
            if self.is_database_locked(db_path):
                result['status'] = 'error'
                result['errors'].append('Database is locked (in use)')
                return result
            
            # Выполняем тестирование и исправление
            repair_result = self.test_and_repair(db_path)
            
            if repair_result['success']:
                result['actions'].append('test_and_repair')
                
                # Получаем размер после обработки
                result['sizeAfter'] = get_size_gb(db_path)
                result['spaceSaved'] = round(result['sizeBefore'] - result['sizeAfter'], 2)
                
                result['status'] = 'success'
            else:
                result['status'] = 'error'
                result['errors'].append(repair_result['error'])
        
        except Exception as e:
            result['status'] = 'error'
            result['errors'].append(f'Unexpected error: {str(e)}')
        finally:
            result['duration'] = int(time.time() - start_time)
        
        return result
    
    def process_all(self) -> List[Dict]:
        """
        Обработать все базы данных.
        
        Returns:
            Список результатов обработки
        """
        # Проверяем наличие платформы
        if not self.find_platform():
            if not self.silent:
                version_mask = self.config.get('platformVersion', 'any')
                print(f'[ERROR] 1C platform not found (version mask: {version_mask})')
            return []
        
        if not self.silent:
            print(f'[INFO] Using 1C platform: {self.platform_version}')
        
        databases = self.find_databases()
        
        if not databases:
            if not self.silent:
                print('[INFO] No 1C databases found')
            return []
        
        if not self.silent:
            print(f'[INFO] Found {len(databases)} 1C databases')
        
        results = []
        for i, db_path in enumerate(databases, 1):
            if not self.silent:
                print(f'[INFO] Processing database {i}/{len(databases)}: {db_path}')
            
            result = self.process_database(db_path)
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


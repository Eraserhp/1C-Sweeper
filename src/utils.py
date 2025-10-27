"""
Утилиты для работы с файловой системой, процессами и платформой 1С.
"""

import os
import re
import shutil
import psutil
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Tuple


def get_size_gb(path: str) -> float:
    """
    Получить размер файла или директории в гигабайтах.
    
    Args:
        path: Путь к файлу или директории
        
    Returns:
        Размер в ГБ с точностью до сотых
    """
    if not os.path.exists(path):
        return 0.0
    
    if os.path.isfile(path):
        size_bytes = os.path.getsize(path)
    else:
        size_bytes = 0
        for dirpath, dirnames, filenames in os.walk(path):
            for filename in filenames:
                filepath = os.path.join(dirpath, filename)
                try:
                    size_bytes += os.path.getsize(filepath)
                except (OSError, FileNotFoundError):
                    # Файл может быть удален или недоступен
                    continue
    
    size_gb = size_bytes / (1024 ** 3)
    return round(size_gb, 2)


def is_path_locked(path: str) -> bool:
    """
    Проверить, заблокирован ли путь другим процессом.
    
    Args:
        path: Путь для проверки
        
    Returns:
        True если заблокирован, False иначе
    """
    # Для файлов проверяем прямую блокировку
    if os.path.isfile(path):
        try:
            # Пытаемся открыть файл в эксклюзивном режиме
            with open(path, 'a'):
                pass
            return False
        except (IOError, OSError):
            return True
    
    # Для директорий проверяем доступность для записи
    if os.path.isdir(path):
        test_file = os.path.join(path, '.sweep_test_lock')
        try:
            with open(test_file, 'w') as f:
                f.write('test')
            os.remove(test_file)
            return False
        except (IOError, OSError):
            return True
    
    return False


def is_process_running(process_names: List[str]) -> bool:
    """
    Проверить, запущен ли хотя бы один из указанных процессов.
    
    Args:
        process_names: Список имен процессов для проверки (без учета регистра)
        
    Returns:
        True если хотя бы один процесс запущен, False иначе
    """
    process_names_lower = [name.lower() for name in process_names]
    
    for proc in psutil.process_iter(['name']):
        try:
            proc_name = proc.info['name']
            if proc_name and proc_name.lower() in process_names_lower:
                return True
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    
    return False


def find_git_repos(search_paths: List[str]) -> List[str]:
    """
    Найти все Git-репозитории в указанных путях (поиск на один уровень вглубь).
    
    Args:
        search_paths: Список путей для поиска
        
    Returns:
        Список путей к найденным репозиториям
    """
    repos = []
    
    for search_path in search_paths:
        if not os.path.exists(search_path):
            continue
        
        # Проверяем сам путь
        if os.path.isdir(os.path.join(search_path, '.git')):
            repos.append(os.path.abspath(search_path))
        
        # Ищем на один уровень вглубь
        try:
            for item in os.listdir(search_path):
                item_path = os.path.join(search_path, item)
                if os.path.isdir(item_path):
                    git_dir = os.path.join(item_path, '.git')
                    if os.path.isdir(git_dir):
                        repos.append(os.path.abspath(item_path))
        except (OSError, PermissionError):
            continue
    
    return list(set(repos))  # Убираем дубликаты


def find_edt_workspaces(search_paths: List[str]) -> List[str]:
    """
    Найти все EDT workspaces в указанных путях (по наличию .metadata).
    
    Args:
        search_paths: Список путей для поиска
        
    Returns:
        Список путей к найденным workspaces
    """
    workspaces = []
    
    for search_path in search_paths:
        if not os.path.exists(search_path):
            continue
        
        # Проверяем сам путь
        if os.path.isdir(os.path.join(search_path, '.metadata')):
            workspaces.append(os.path.abspath(search_path))
        
        # Ищем на один уровень вглубь
        try:
            for item in os.listdir(search_path):
                item_path = os.path.join(search_path, item)
                if os.path.isdir(item_path):
                    metadata_dir = os.path.join(item_path, '.metadata')
                    if os.path.isdir(metadata_dir):
                        workspaces.append(os.path.abspath(item_path))
        except (OSError, PermissionError):
            continue
    
    return list(set(workspaces))  # Убираем дубликаты


def find_1c_databases(search_paths: List[str]) -> List[str]:
    """
    Найти все информационные базы 1С (файлы .1CD) в указанных путях.
    
    Args:
        search_paths: Список путей для поиска
        
    Returns:
        Список путей к найденным базам
    """
    databases = []
    
    for search_path in search_paths:
        if not os.path.exists(search_path):
            continue
        
        # Если это файл .1CD
        if os.path.isfile(search_path) and search_path.lower().endswith('.1cd'):
            databases.append(os.path.abspath(search_path))
            continue
        
        # Ищем файлы .1CD в директории
        if os.path.isdir(search_path):
            try:
                for root, dirs, files in os.walk(search_path):
                    for file in files:
                        if file.lower().endswith('.1cd'):
                            databases.append(os.path.abspath(os.path.join(root, file)))
            except (OSError, PermissionError):
                continue
    
    return list(set(databases))  # Убираем дубликаты


def find_1c_platform(version_mask: Optional[str] = None) -> Optional[Tuple[str, str]]:
    """
    Найти установленную платформу 1С, соответствующую маске версии.
    
    Args:
        version_mask: Маска версии (например, "8.3.27", "8.3.*", "8.3.2[0-9]")
                     Если None, возвращается максимальная найденная версия
        
    Returns:
        Кортеж (путь к 1cv8.exe, версия) или None если не найдена
    """
    platform_paths = [
        r"C:\Program Files\1cv8",
        r"C:\Program Files (x86)\1cv8",
    ]
    
    found_versions = []
    
    for base_path in platform_paths:
        if not os.path.exists(base_path):
            continue
        
        try:
            for item in os.listdir(base_path):
                item_path = os.path.join(base_path, item)
                if os.path.isdir(item_path):
                    bin_path = os.path.join(item_path, 'bin', '1cv8.exe')
                    if os.path.isfile(bin_path):
                        # Извлекаем версию из имени папки
                        version_match = re.match(r'(\d+\.\d+\.\d+\.\d+)', item)
                        if version_match:
                            version = version_match.group(1)
                            found_versions.append((bin_path, version))
        except (OSError, PermissionError):
            continue
    
    if not found_versions:
        return None
    
    # Фильтруем по маске версии если указана
    if version_mask:
        # Преобразуем маску в регулярное выражение
        # "8.3.27" -> "8\.3\.27\..*"
        # "8.3.*" -> "8\.3\..*"
        # "8.3.2[0-9]" -> "8\.3\.2[0-9]\..*"
        
        mask_pattern = version_mask.replace('.', r'\.')
        if not mask_pattern.endswith('*') and not mask_pattern.endswith(']'):
            mask_pattern += r'\..*'
        else:
            mask_pattern = mask_pattern.replace('*', '.*')
            if not mask_pattern.endswith('.*'):
                mask_pattern += r'\..*'
        
        mask_regex = re.compile(f'^{mask_pattern}$')
        
        filtered_versions = [
            (path, ver) for path, ver in found_versions
            if mask_regex.match(ver)
        ]
        
        if not filtered_versions:
            return None
        
        found_versions = filtered_versions
    
    # Возвращаем максимальную версию
    found_versions.sort(key=lambda x: [int(p) for p in x[1].split('.')])
    return found_versions[-1]


def safe_remove_file(filepath: str) -> bool:
    """
    Безопасно удалить файл.
    
    Args:
        filepath: Путь к файлу
        
    Returns:
        True если успешно удален, False иначе
    """
    try:
        if os.path.exists(filepath):
            os.remove(filepath)
        return True
    except (OSError, PermissionError):
        return False


def safe_remove_dir(dirpath: str) -> bool:
    """
    Безопасно удалить директорию со всем содержимым.
    
    Args:
        dirpath: Путь к директории
        
    Returns:
        True если успешно удалена, False иначе
    """
    try:
        if os.path.exists(dirpath):
            shutil.rmtree(dirpath)
        return True
    except (OSError, PermissionError):
        return False


def ensure_dir(dirpath: str) -> bool:
    """
    Убедиться что директория существует, создать если нет.
    
    Args:
        dirpath: Путь к директории
        
    Returns:
        True если директория существует или создана, False при ошибке
    """
    try:
        os.makedirs(dirpath, exist_ok=True)
        return True
    except (OSError, PermissionError):
        return False


def get_timestamp() -> str:
    """
    Получить текущую временную метку в формате для логов.
    
    Returns:
        Строка с временной меткой в формате [YYYY-MM-DD HH:MM:SS]
    """
    now = datetime.now()
    return now.strftime('[%Y-%m-%d %H:%M:%S]')


def format_log_message(level: str, message: str) -> str:
    """
    Форматировать сообщение лога с временной меткой.
    
    Args:
        level: Уровень лога (INFO, OK, ERROR, WARNING, SUCCESS)
        message: Текст сообщения
        
    Returns:
        Отформатированное сообщение с временной меткой
    """
    timestamp = get_timestamp()
    return f'{timestamp} [{level}] {message}'


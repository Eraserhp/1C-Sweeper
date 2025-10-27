"""
Тесты для модуля utils.
"""

import os
import tempfile
import pytest
from pathlib import Path
from src.utils import (
    get_size_gb,
    find_git_repos,
    find_edt_workspaces,
    find_1c_databases,
    find_1c_platform,
    ensure_dir,
    safe_remove_file,
    safe_remove_dir
)


class TestGetSizeGb:
    """Тесты функции get_size_gb."""
    
    def test_nonexistent_path(self):
        """Тест для несуществующего пути."""
        assert get_size_gb('/nonexistent/path') == 0.0
    
    def test_empty_file(self, tmp_path):
        """Тест для пустого файла."""
        test_file = tmp_path / "empty.txt"
        test_file.write_text("")
        assert get_size_gb(str(test_file)) == 0.0
    
    def test_file_with_content(self, tmp_path):
        """Тест для файла с содержимым."""
        test_file = tmp_path / "test.txt"
        # Создаем файл размером примерно 1 МБ
        test_file.write_bytes(b'0' * (1024 * 1024))
        size = get_size_gb(str(test_file))
        assert 0.0009 < size < 0.002  # Примерно 0.001 ГБ
    
    def test_directory_size(self, tmp_path):
        """Тест для директории с файлами."""
        # Создаем несколько файлов
        for i in range(3):
            test_file = tmp_path / f"file{i}.txt"
            test_file.write_bytes(b'0' * (1024 * 1024))  # 1 МБ каждый
        
        size = get_size_gb(str(tmp_path))
        assert 0.002 < size < 0.005  # Примерно 0.003 ГБ


class TestFindGitRepos:
    """Тесты функции find_git_repos."""
    
    def test_find_repos_in_directory(self, tmp_path):
        """Тест поиска репозиториев в директории."""
        # Создаем структуру с репозиториями
        repo1 = tmp_path / "repo1"
        repo1.mkdir()
        (repo1 / ".git").mkdir()
        
        repo2 = tmp_path / "repo2"
        repo2.mkdir()
        (repo2 / ".git").mkdir()
        
        # Поиск
        found_repos = find_git_repos([str(tmp_path)])
        
        assert len(found_repos) == 2
        assert str(repo1) in found_repos or str(repo1.resolve()) in found_repos
        assert str(repo2) in found_repos or str(repo2.resolve()) in found_repos
    
    def test_no_repos_found(self, tmp_path):
        """Тест когда репозитории не найдены."""
        found_repos = find_git_repos([str(tmp_path)])
        assert len(found_repos) == 0
    
    def test_nonexistent_search_path(self):
        """Тест для несуществующего пути поиска."""
        found_repos = find_git_repos(['/nonexistent/path'])
        assert len(found_repos) == 0


class TestFindEdtWorkspaces:
    """Тесты функции find_edt_workspaces."""
    
    def test_find_workspaces(self, tmp_path):
        """Тест поиска workspaces."""
        # Создаем workspace
        ws1 = tmp_path / "workspace1"
        ws1.mkdir()
        (ws1 / ".metadata").mkdir()
        
        ws2 = tmp_path / "workspace2"
        ws2.mkdir()
        (ws2 / ".metadata").mkdir()
        
        # Поиск
        found_workspaces = find_edt_workspaces([str(tmp_path)])
        
        assert len(found_workspaces) == 2
    
    def test_no_workspaces_found(self, tmp_path):
        """Тест когда workspaces не найдены."""
        found_workspaces = find_edt_workspaces([str(tmp_path)])
        assert len(found_workspaces) == 0


class TestFind1cDatabases:
    """Тесты функции find_1c_databases."""
    
    def test_find_databases(self, tmp_path):
        """Тест поиска баз данных."""
        # Создаем базы
        db1 = tmp_path / "base1" / "1Cv8.1CD"
        db1.parent.mkdir()
        db1.write_text("test")
        
        db2 = tmp_path / "base2" / "1Cv8.1CD"
        db2.parent.mkdir()
        db2.write_text("test")
        
        # Поиск
        found_databases = find_1c_databases([str(tmp_path)])
        
        assert len(found_databases) == 2
    
    def test_case_insensitive(self, tmp_path):
        """Тест что поиск не зависит от регистра."""
        db = tmp_path / "1cv8.1cd"  # Нижний регистр
        db.write_text("test")
        
        found_databases = find_1c_databases([str(tmp_path)])
        
        assert len(found_databases) == 1


class TestFind1cPlatform:
    """Тесты функции find_1c_platform."""
    
    def test_platform_not_found(self):
        """Тест когда платформа не найдена."""
        # С нестандартной маской версии, которая точно не существует
        result = find_1c_platform("9.9.99")
        assert result is None
    
    def test_no_version_mask(self):
        """Тест без маски версии."""
        # Функция должна искать любую версию
        # Может вернуть None если платформа не установлена
        result = find_1c_platform(None)
        # Не проверяем результат, т.к. зависит от системы


class TestEnsureDir:
    """Тесты функции ensure_dir."""
    
    def test_create_directory(self, tmp_path):
        """Тест создания директории."""
        new_dir = tmp_path / "new_directory"
        assert not new_dir.exists()
        
        result = ensure_dir(str(new_dir))
        
        assert result is True
        assert new_dir.exists()
        assert new_dir.is_dir()
    
    def test_existing_directory(self, tmp_path):
        """Тест для существующей директории."""
        existing_dir = tmp_path / "existing"
        existing_dir.mkdir()
        
        result = ensure_dir(str(existing_dir))
        
        assert result is True
        assert existing_dir.exists()


class TestSafeRemoveFile:
    """Тесты функции safe_remove_file."""
    
    def test_remove_existing_file(self, tmp_path):
        """Тест удаления существующего файла."""
        test_file = tmp_path / "test.txt"
        test_file.write_text("test content")
        
        result = safe_remove_file(str(test_file))
        
        assert result is True
        assert not test_file.exists()
    
    def test_remove_nonexistent_file(self):
        """Тест удаления несуществующего файла."""
        result = safe_remove_file('/nonexistent/file.txt')
        assert result is True  # Считаем успехом если файла и так нет


class TestSafeRemoveDir:
    """Тесты функции safe_remove_dir."""
    
    def test_remove_directory(self, tmp_path):
        """Тест удаления директории."""
        test_dir = tmp_path / "test_dir"
        test_dir.mkdir()
        (test_dir / "file.txt").write_text("content")
        
        result = safe_remove_dir(str(test_dir))
        
        assert result is True
        assert not test_dir.exists()
    
    def test_remove_nonexistent_directory(self):
        """Тест удаления несуществующей директории."""
        result = safe_remove_dir('/nonexistent/directory')
        assert result is True  # Считаем успехом если директории и так нет


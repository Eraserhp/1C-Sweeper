"""
Тесты для модуля db_handler.
"""

import base64
import pytest
from unittest.mock import Mock, patch
from src.db_handler import DatabaseHandler


class TestDatabaseHandler:
    """Тесты класса DatabaseHandler."""
    
    def test_init(self):
        """Тест инициализации обработчика."""
        config = {
            'databases': ['C:\\Bases\\Test\\1Cv8.1CD'],
            'searchPaths': ['C:\\Bases'],
            'platformVersion': '8.3.27',
            'sizeThresholdGB': 3
        }
        
        handler = DatabaseHandler(config, silent=True)
        
        assert handler.config == config
        assert handler.silent is True
        assert handler.results == []
        assert handler.platform_path is None
        assert handler.platform_version is None
    
    @patch('src.db_handler.find_1c_platform')
    def test_find_platform_success(self, mock_find):
        """Тест поиска платформы (успех)."""
        mock_find.return_value = ('C:\\Program Files\\1cv8\\8.3.27.1234\\bin\\1cv8.exe', '8.3.27.1234')
        
        config = {'platformVersion': '8.3.27'}
        handler = DatabaseHandler(config)
        
        result = handler.find_platform()
        
        assert result is True
        assert handler.platform_path is not None
        assert handler.platform_version == '8.3.27.1234'
    
    @patch('src.db_handler.find_1c_platform')
    def test_find_platform_failure(self, mock_find):
        """Тест поиска платформы (не найдена)."""
        mock_find.return_value = None
        
        config = {'platformVersion': '8.3.27'}
        handler = DatabaseHandler(config)
        
        result = handler.find_platform()
        
        assert result is False
        assert handler.platform_path is None
    
    def test_find_databases_explicit(self, tmp_path):
        """Тест поиска явно указанных баз."""
        # Создаем тестовую базу
        db_path = tmp_path / "1Cv8.1CD"
        db_path.write_text("test database")
        
        config = {
            'databases': [str(db_path)],
            'searchPaths': []
        }
        
        handler = DatabaseHandler(config)
        databases = handler.find_databases()
        
        assert len(databases) == 1
        assert str(db_path) in databases[0]
    
    def test_get_auth_params_no_auth(self):
        """Тест получения параметров аутентификации (не указаны)."""
        config = {}
        handler = DatabaseHandler(config)
        
        username, password = handler.get_auth_params()
        
        assert username is None
        assert password is None
    
    def test_get_auth_params_with_auth(self):
        """Тест получения параметров аутентификации (указаны)."""
        # Кодируем пароль в Base64
        password_plain = "TestPassword123"
        password_b64 = base64.b64encode(password_plain.encode('utf-8')).decode('utf-8')
        
        config = {
            'user': 'Admin',
            'password': password_b64
        }
        handler = DatabaseHandler(config)
        
        username, password = handler.get_auth_params()
        
        assert username == 'Admin'
        assert password == password_plain
    
    def test_process_database_not_found(self):
        """Тест обработки несуществующей базы."""
        config = {'databases': [], 'sizeThresholdGB': 3}
        handler = DatabaseHandler(config)
        
        result = handler.process_database('C:\\Nonexistent\\1Cv8.1CD')
        
        assert result['status'] == 'error'
        assert 'not found' in result['errors'][0]
    
    def test_process_database_below_threshold(self, tmp_path):
        """Тест пропуска базы ниже порога."""
        # Создаем маленькую базу
        db_path = tmp_path / "1Cv8.1CD"
        db_path.write_text("small database")
        
        config = {'databases': [], 'sizeThresholdGB': 3}
        handler = DatabaseHandler(config)
        
        result = handler.process_database(str(db_path))
        
        assert result['status'] == 'skipped'
        assert 'below threshold' in result['errors'][0]
    
    @patch('subprocess.run')
    def test_test_and_repair_success(self, mock_run):
        """Тест успешного тестирования и исправления."""
        mock_run.return_value = Mock(returncode=0)
        
        config = {}
        handler = DatabaseHandler(config)
        handler.platform_path = 'C:\\Program Files\\1cv8\\bin\\1cv8.exe'
        
        result = handler.test_and_repair('C:\\Bases\\Test\\1Cv8.1CD')
        
        assert result['success'] is True
        assert result['error'] is None
    
    @patch('subprocess.run')
    def test_test_and_repair_failure(self, mock_run):
        """Тест неудачного тестирования и исправления."""
        mock_run.return_value = Mock(returncode=1, stderr='Error message')
        
        config = {}
        handler = DatabaseHandler(config)
        handler.platform_path = 'C:\\Program Files\\1cv8\\bin\\1cv8.exe'
        
        result = handler.test_and_repair('C:\\Bases\\Test\\1Cv8.1CD')
        
        assert result['success'] is False
        assert result['error'] is not None


"""
Интеграционные тесты для основного модуля maintenance.
"""

import json
import os
import pytest
from unittest.mock import Mock, patch
from src.maintenance import MaintenanceSystem


class TestMaintenanceSystem:
    """Интеграционные тесты системы обслуживания."""
    
    def test_init(self):
        """Тест инициализации системы."""
        system = MaintenanceSystem('test-config.json', silent=True)
        
        assert system.config_path == 'test-config.json'
        assert system.silent is True
        assert system.config is None
    
    def test_load_config_success(self, tmp_path):
        """Тест успешной загрузки конфигурации."""
        # Создаем тестовую конфигурацию
        config_file = tmp_path / "test-config.json"
        test_config = {
            'settings': {
                'git': {'repos': [], 'searchPaths': [], 'sizeThresholdGB': 15},
                'general': {'reportsPath': './reports'}
            }
        }
        config_file.write_text(json.dumps(test_config))
        
        system = MaintenanceSystem(str(config_file))
        result = system.load_config()
        
        assert result is True
        assert system.config is not None
        assert 'settings' in system.config
    
    def test_load_config_not_found(self):
        """Тест загрузки несуществующей конфигурации."""
        system = MaintenanceSystem('/nonexistent/config.json', silent=True)
        result = system.load_config()
        
        assert result is False
        assert system.config is None
    
    def test_load_config_invalid_json(self, tmp_path):
        """Тест загрузки невалидного JSON."""
        config_file = tmp_path / "invalid-config.json"
        config_file.write_text('{ invalid json }')
        
        system = MaintenanceSystem(str(config_file), silent=True)
        result = system.load_config()
        
        assert result is False
    
    def test_validate_config_missing_settings(self):
        """Тест валидации конфигурации без секции settings."""
        system = MaintenanceSystem('test.json')
        system.config = {'some': 'data'}
        
        result = system.validate_config()
        
        assert result is False
    
    def test_validate_config_no_handlers(self):
        """Тест валидации конфигурации без обработчиков."""
        system = MaintenanceSystem('test.json')
        system.config = {'settings': {}}
        
        result = system.validate_config()
        
        assert result is False
    
    def test_validate_config_success(self):
        """Тест успешной валидации конфигурации."""
        system = MaintenanceSystem('test.json')
        system.config = {
            'settings': {
                'git': {'repos': []},
                'general': {}
            }
        }
        
        result = system.validate_config()
        
        assert result is True
    
    def test_log_methods_silent(self, capsys):
        """Тест что в тихом режиме не выводятся сообщения (кроме ошибок)."""
        system = MaintenanceSystem('test.json', silent=True)
        
        system.log_info('Test info')
        system.log_success('Test success')
        system.log_warning('Test warning')
        
        captured = capsys.readouterr()
        assert captured.out == ''
        
        # Ошибки выводятся даже в тихом режиме
        system.log_error('Test error')
        captured = capsys.readouterr()
        assert 'ERROR' in captured.err
    
    @patch('src.maintenance.GitHandler')
    @patch('src.maintenance.EdtHandler')
    @patch('src.maintenance.DatabaseHandler')
    @patch('src.maintenance.Reporter')
    def test_run_success(self, mock_reporter, mock_db_handler, mock_edt_handler, mock_git_handler, tmp_path):
        """Тест успешного выполнения обслуживания."""
        # Создаем конфигурацию
        config_file = tmp_path / "config.json"
        test_config = {
            'settings': {
                'git': {'repos': [], 'searchPaths': [], 'sizeThresholdGB': 15},
                'edt': {'workspaces': [], 'searchPaths': [], 'sizeThresholdGB': 5},
                'database': {'databases': [], 'searchPaths': [], 'sizeThresholdGB': 3},
                'general': {'reportsPath': str(tmp_path / 'reports'), 'silentMode': False}
            }
        }
        config_file.write_text(json.dumps(test_config))
        
        # Мокируем обработчики
        mock_git_instance = Mock()
        mock_git_instance.process_all.return_value = []
        mock_git_handler.return_value = mock_git_instance
        
        mock_edt_instance = Mock()
        mock_edt_instance.process_all.return_value = []
        mock_edt_handler.return_value = mock_edt_instance
        
        mock_db_instance = Mock()
        mock_db_instance.process_all.return_value = []
        mock_db_handler.return_value = mock_db_instance
        
        # Мокируем репортер
        mock_reporter_instance = Mock()
        mock_reporter_instance.generate_report.return_value = {'summary': {}}
        mock_reporter_instance.save_report.return_value = 'test_report.json'
        mock_reporter.return_value = mock_reporter_instance
        
        # Запускаем систему
        system = MaintenanceSystem(str(config_file), silent=True)
        exit_code = system.run()
        
        # Проверяем что все обработчики были вызваны
        assert mock_git_instance.process_all.called
        assert mock_edt_instance.process_all.called
        assert mock_db_instance.process_all.called
        assert mock_reporter_instance.generate_report.called
        assert mock_reporter_instance.save_report.called
        
        # Проверяем код возврата
        assert exit_code == 0
    
    def test_run_config_not_found(self):
        """Тест запуска с несуществующей конфигурацией."""
        system = MaintenanceSystem('/nonexistent/config.json', silent=True)
        exit_code = system.run()
        
        assert exit_code == 1


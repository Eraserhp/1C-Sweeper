"""
Тесты для модуля edt_handler.
"""

import pytest
from unittest.mock import Mock, patch
from src.edt_handler import EdtHandler


class TestEdtHandler:
    """Тесты класса EdtHandler."""
    
    def test_init(self):
        """Тест инициализации обработчика."""
        config = {
            'workspaces': ['C:\\EDT\\Workspace1'],
            'searchPaths': ['C:\\EDT'],
            'sizeThresholdGB': 5
        }
        
        handler = EdtHandler(config, silent=True)
        
        assert handler.config == config
        assert handler.silent is True
        assert handler.results == []
    
    def test_find_workspaces_explicit(self, tmp_path):
        """Тест поиска явно указанных workspaces."""
        # Создаем тестовый workspace
        ws_path = tmp_path / "test_workspace"
        ws_path.mkdir()
        (ws_path / ".metadata").mkdir()
        
        config = {
            'workspaces': [str(ws_path)],
            'searchPaths': []
        }
        
        handler = EdtHandler(config)
        workspaces = handler.find_workspaces()
        
        assert len(workspaces) == 1
        assert str(ws_path) in workspaces[0]
    
    def test_is_workspace_locked_no_lock(self, tmp_path):
        """Тест проверки блокировки workspace (не заблокирован)."""
        ws_path = tmp_path / "workspace"
        ws_path.mkdir()
        (ws_path / ".metadata").mkdir()
        
        config = {}
        handler = EdtHandler(config)
        
        # Без запущенных процессов EDT
        with patch('src.edt_handler.is_process_running', return_value=False):
            result = handler.is_workspace_locked(str(ws_path))
        
        assert result is False
    
    def test_is_workspace_locked_with_lock_file(self, tmp_path):
        """Тест проверки блокировки workspace (есть .lock файл)."""
        ws_path = tmp_path / "workspace"
        ws_path.mkdir()
        metadata = ws_path / ".metadata"
        metadata.mkdir()
        (metadata / ".lock").write_text("locked")
        
        config = {}
        handler = EdtHandler(config)
        
        result = handler.is_workspace_locked(str(ws_path))
        
        assert result is True
    
    def test_is_workspace_locked_with_edt_running(self, tmp_path):
        """Тест проверки блокировки workspace (EDT запущен)."""
        ws_path = tmp_path / "workspace"
        ws_path.mkdir()
        (ws_path / ".metadata").mkdir()
        
        config = {}
        handler = EdtHandler(config)
        
        # EDT запущен
        with patch('src.edt_handler.is_process_running', return_value=True):
            result = handler.is_workspace_locked(str(ws_path))
        
        assert result is True
    
    def test_clean_workspace(self, tmp_path):
        """Тест очистки workspace."""
        # Создаем структуру workspace
        ws_path = tmp_path / "workspace"
        metadata = ws_path / ".metadata"
        metadata.mkdir(parents=True)
        
        # Создаем лог-файл
        log_file = metadata / ".log"
        log_file.write_text("log content")
        
        config = {}
        handler = EdtHandler(config)
        
        stats = handler.clean_workspace(str(ws_path))
        
        assert isinstance(stats, dict)
        assert 'logsCleared' in stats
        assert 'historyCleared' in stats
        assert 'snapshotsCleared' in stats
        assert 'cachesCleared' in stats
    
    def test_process_workspace_not_a_workspace(self, tmp_path):
        """Тест обработки не-workspace."""
        config = {'workspaces': [], 'sizeThresholdGB': 5}
        handler = EdtHandler(config)
        
        result = handler.process_workspace(str(tmp_path))
        
        assert result['status'] == 'error'
        assert 'Not an EDT workspace' in result['errors'][0]
    
    def test_process_workspace_below_threshold(self, tmp_path):
        """Тест пропуска workspace ниже порога."""
        # Создаем маленький workspace
        ws_path = tmp_path / "small_workspace"
        ws_path.mkdir()
        (ws_path / ".metadata").mkdir()
        
        config = {'workspaces': [], 'sizeThresholdGB': 5}
        handler = EdtHandler(config)
        
        result = handler.process_workspace(str(ws_path))
        
        assert result['status'] == 'skipped'
        assert 'below threshold' in result['errors'][0]


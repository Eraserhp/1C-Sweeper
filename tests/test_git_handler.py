"""
Тесты для модуля git_handler.
"""

import pytest
from unittest.mock import Mock, patch, MagicMock
from src.git_handler import GitHandler


class TestGitHandler:
    """Тесты класса GitHandler."""
    
    def test_init(self):
        """Тест инициализации обработчика."""
        config = {
            'repos': ['C:\\Dev\\Repo1'],
            'searchPaths': ['C:\\Dev'],
            'sizeThresholdGB': 15
        }
        
        handler = GitHandler(config, silent=True)
        
        assert handler.config == config
        assert handler.silent is True
        assert handler.results == []
    
    @patch('subprocess.run')
    def test_check_git_available_success(self, mock_run):
        """Тест проверки доступности Git (успех)."""
        mock_run.return_value = Mock(returncode=0)
        
        config = {'repos': []}
        handler = GitHandler(config)
        
        result = handler.check_git_available()
        
        assert result is True
        mock_run.assert_called_once()
    
    @patch('subprocess.run')
    def test_check_git_available_failure(self, mock_run):
        """Тест проверки доступности Git (не найден)."""
        mock_run.side_effect = FileNotFoundError()
        
        config = {'repos': []}
        handler = GitHandler(config)
        
        result = handler.check_git_available()
        
        assert result is False
    
    def test_find_repositories_explicit(self, tmp_path):
        """Тест поиска явно указанных репозиториев."""
        # Создаем тестовый репозиторий
        repo_path = tmp_path / "test_repo"
        repo_path.mkdir()
        (repo_path / ".git").mkdir()
        
        config = {
            'repos': [str(repo_path)],
            'searchPaths': []
        }
        
        handler = GitHandler(config)
        repos = handler.find_repositories()
        
        assert len(repos) == 1
        assert str(repo_path) in repos[0]
    
    @patch('subprocess.run')
    def test_get_garbage_info(self, mock_run):
        """Тест получения информации о garbage."""
        # Мокируем вывод git count-objects -v
        mock_run.return_value = Mock(
            returncode=0,
            stdout='count: 1000\nsize: 4096\nsize-garbage: 2097152\n'
        )
        
        config = {'repos': []}
        handler = GitHandler(config)
        
        garbage_info = handler.get_garbage_info('C:\\Dev\\Repo')
        
        assert garbage_info['size_gb'] == 2.0  # 2097152 KB = 2 GB
    
    def test_process_repository_not_a_repo(self, tmp_path):
        """Тест обработки не-репозитория."""
        config = {'repos': [], 'sizeThresholdGB': 15}
        handler = GitHandler(config)
        
        result = handler.process_repository(str(tmp_path))
        
        assert result['status'] == 'error'
        assert 'Not a Git repository' in result['errors']
    
    def test_process_repository_below_threshold(self, tmp_path):
        """Тест пропуска репозитория ниже порога."""
        # Создаем маленький репозиторий
        repo_path = tmp_path / "small_repo"
        repo_path.mkdir()
        (repo_path / ".git").mkdir()
        
        config = {'repos': [], 'sizeThresholdGB': 15}
        handler = GitHandler(config)
        
        result = handler.process_repository(str(repo_path))
        
        assert result['status'] == 'skipped'
        assert 'below threshold' in result['errors'][0]


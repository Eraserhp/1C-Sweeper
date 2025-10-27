"""
Тесты для модуля reporter.
"""

import json
import os
import tempfile
from datetime import datetime
from src.reporter import Reporter


class TestReporter:
    """Тесты класса Reporter."""
    
    def test_generate_report_empty(self, tmp_path):
        """Тест генерации пустого отчета."""
        reporter = Reporter(str(tmp_path))
        
        start_time = datetime(2025, 10, 21, 20, 0, 0)
        end_time = datetime(2025, 10, 21, 20, 5, 0)
        
        report = reporter.generate_report([], [], [], start_time, end_time)
        
        assert report['reportVersion'] == '1.0'
        assert report['duration'] == 300  # 5 минут
        assert report['summary']['totalSpaceSaved'] == 0.0
        assert report['summary']['gitReposProcessed'] == 0
        assert report['summary']['workspacesProcessed'] == 0
        assert report['summary']['databasesProcessed'] == 0
        assert len(report['errors']) == 0
    
    def test_generate_report_with_results(self, tmp_path):
        """Тест генерации отчета с результатами."""
        reporter = Reporter(str(tmp_path))
        
        git_results = [{
            'path': 'C:\\Dev\\Repo1',
            'sizeBefore': 25.0,
            'sizeAfter': 15.0,
            'spaceSaved': 10.0,
            'status': 'success',
            'errors': []
        }]
        
        edt_results = [{
            'path': 'C:\\EDT\\Workspace1',
            'sizeBefore': 8.0,
            'sizeAfter': 2.0,
            'spaceSaved': 6.0,
            'status': 'success',
            'errors': []
        }]
        
        db_results = [{
            'path': 'C:\\Bases\\1Cv8.1CD',
            'sizeBefore': 5.0,
            'sizeAfter': 3.0,
            'spaceSaved': 2.0,
            'status': 'success',
            'errors': []
        }]
        
        start_time = datetime(2025, 10, 21, 20, 0, 0)
        end_time = datetime(2025, 10, 21, 20, 30, 0)
        
        report = reporter.generate_report(
            git_results, edt_results, db_results, start_time, end_time
        )
        
        assert report['summary']['totalSpaceSaved'] == 18.0
        assert report['summary']['gitReposProcessed'] == 1
        assert report['summary']['gitReposSuccess'] == 1
        assert report['summary']['workspacesProcessed'] == 1
        assert report['summary']['databasesProcessed'] == 1
    
    def test_generate_report_with_errors(self, tmp_path):
        """Тест генерации отчета с ошибками."""
        reporter = Reporter(str(tmp_path))
        
        git_results = [{
            'path': 'C:\\Dev\\Repo1',
            'spaceSaved': 0.0,
            'status': 'error',
            'errors': ['Repository locked']
        }]
        
        start_time = datetime(2025, 10, 21, 20, 0, 0)
        end_time = datetime(2025, 10, 21, 20, 5, 0)
        
        report = reporter.generate_report(git_results, [], [], start_time, end_time)
        
        assert report['summary']['gitReposFailed'] == 1
        assert len(report['errors']) == 1
        assert report['errors'][0]['type'] == 'git'
    
    def test_save_report(self, tmp_path):
        """Тест сохранения отчета."""
        reporter = Reporter(str(tmp_path))
        
        test_report = {
            'reportVersion': '1.0',
            'timestamp': '2025-10-21T20:00:00',
            'summary': {'totalSpaceSaved': 10.0}
        }
        
        report_path = reporter.save_report(test_report)
        
        assert os.path.exists(report_path)
        assert report_path.endswith('.json')
        
        # Проверяем содержимое
        with open(report_path, 'r', encoding='utf-8') as f:
            loaded_report = json.load(f)
        
        assert loaded_report['reportVersion'] == '1.0'
        assert loaded_report['summary']['totalSpaceSaved'] == 10.0
    
    def test_print_summary_silent(self, tmp_path, capsys):
        """Тест что print_summary не выводит ничего в тихом режиме."""
        reporter = Reporter(str(tmp_path))
        
        test_report = {
            'duration': 300,
            'summary': {
                'totalSpaceSaved': 10.0,
                'gitReposProcessed': 1,
                'gitReposSuccess': 1,
                'gitReposFailed': 0,
                'workspacesProcessed': 0,
                'workspacesSuccess': 0,
                'workspacesFailed': 0,
                'databasesProcessed': 0,
                'databasesSuccess': 0,
                'databasesFailed': 0
            },
            'errors': []
        }
        
        reporter.print_summary(test_report, silent=True)
        
        captured = capsys.readouterr()
        assert captured.out == ''


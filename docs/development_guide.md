# Руководство разработчика 1C-Sweeper

## Установка для разработки

### 1. Клонирование репозитория

```bash
git clone https://github.com/yourusername/1C-Sweeper.git
cd 1C-Sweeper
```

### 2. Создание виртуального окружения

```bash
# Windows
python -m venv venv
venv\Scripts\activate

# Linux/Mac
python3 -m venv venv
source venv/bin/activate
```

### 3. Установка зависимостей

```bash
pip install -r requirements.txt
```

## Структура проекта

```
1C-Sweeper/
├── src/                        # Исходный код
│   ├── __init__.py
│   ├── maintenance.py          # Основной модуль
│   ├── git_handler.py          # Обработчик Git
│   ├── edt_handler.py          # Обработчик EDT
│   ├── db_handler.py           # Обработчик баз 1С
│   ├── reporter.py             # Генератор отчетов
│   └── utils.py                # Утилиты
├── tests/                      # Тесты
│   ├── __init__.py
│   ├── test_utils.py
│   ├── test_git_handler.py
│   ├── test_edt_handler.py
│   ├── test_db_handler.py
│   ├── test_reporter.py
│   ├── test_maintenance.py
│   └── fixtures/               # Тестовые данные
│       └── mock_config.json
├── docs/                       # Документация
│   ├── technical_specification.md
│   ├── implementation_plan.md
│   └── development_guide.md
├── install.py                  # Установщик
├── requirements.txt            # Python зависимости
├── pytest.ini                  # Конфигурация pytest
├── .coveragerc                 # Конфигурация coverage
├── .gitignore                  # Git ignore
├── README.md                   # Основная документация
├── LICENSE                     # Лицензия
└── maintenance-config.example.json  # Пример конфигурации
```

## Запуск тестов

### Все тесты

```bash
pytest tests/
```

### С покрытием кода

```bash
pytest --cov=src tests/
```

### HTML отчет о покрытии

```bash
pytest --cov=src --cov-report=html tests/
# Откройте htmlcov/index.html в браузере
```

### Конкретный тестовый файл

```bash
pytest tests/test_utils.py
```

### С детальным выводом

```bash
pytest -v tests/
```

## Разработка

### Добавление нового функционала

1. Создайте ветку для новой функции:
```bash
git checkout -b feature/new-feature
```

2. Реализуйте функциональность

3. Добавьте тесты

4. Убедитесь что все тесты проходят:
```bash
pytest tests/
```

5. Проверьте покрытие кода (минимум 70%)

6. Создайте Pull Request

### Кодстайл

- Следуйте PEP 8
- Используйте docstring для всех публичных функций и классов
- Комментируйте сложные участки кода
- Максимальная длина строки: 100 символов

### Документирование

Каждая функция должна иметь docstring в формате:

```python
def function_name(param1: Type1, param2: Type2) -> ReturnType:
    """
    Краткое описание функции.
    
    Args:
        param1: Описание параметра 1
        param2: Описание параметра 2
        
    Returns:
        Описание возвращаемого значения
        
    Raises:
        ExceptionType: Условия возникновения исключения
    """
    pass
```

## Тестирование

### Принципы тестирования

1. **Unit тесты**: Тестируют отдельные функции в изоляции
2. **Integration тесты**: Тестируют взаимодействие компонентов
3. **Mock объекты**: Используются для изоляции тестов от внешних зависимостей

### Создание тестов

Пример unit теста:

```python
def test_get_size_gb(tmp_path):
    """Тест функции get_size_gb."""
    test_file = tmp_path / "test.txt"
    test_file.write_bytes(b'0' * (1024 * 1024))  # 1 МБ
    
    size = get_size_gb(str(test_file))
    
    assert 0.0009 < size < 0.002  # Примерно 0.001 ГБ
```

Пример теста с mock:

```python
@patch('subprocess.run')
def test_check_git_available(mock_run):
    """Тест проверки доступности Git."""
    mock_run.return_value = Mock(returncode=0)
    
    handler = GitHandler({})
    result = handler.check_git_available()
    
    assert result is True
```

### Fixtures

Используйте pytest fixtures для переиспользуемых тестовых данных:

```python
@pytest.fixture
def mock_config():
    """Фикстура с тестовой конфигурацией."""
    return {
        'repos': ['C:\\Dev\\TestRepo'],
        'searchPaths': [],
        'sizeThresholdGB': 15
    }
```

## Отладка

### Запуск с отладочной информацией

```bash
# Детальный вывод
python -m src.maintenance --config test-config.json

# С точками останова (используйте breakpoint() в коде)
python -m pdb -m src.maintenance
```

### Просмотр логов

Логи выводятся в консоль. В тихом режиме только ошибки:

```bash
python -m src.maintenance --silent
```

## Создание релиза

1. Обновите версию в `src/__init__.py`

2. Обновите `README.md` с новыми возможностями

3. Убедитесь что все тесты проходят

4. Создайте git tag:
```bash
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0
```

## Continuous Integration (будущее)

Планируется настройка:

- GitHub Actions для автоматического запуска тестов
- Проверка кодстайла (flake8, black)
- Проверка покрытия кода
- Автоматическая сборка документации

## Участие в проекте

### Процесс внесения изменений

1. Fork репозитория
2. Создайте ветку для изменений
3. Внесите изменения с тестами
4. Убедитесь что тесты проходят
5. Создайте Pull Request с подробным описанием

### Code Review

Все Pull Request'ы проходят review:

- Проверка соответствия кодстайлу
- Наличие тестов
- Качество документации
- Отсутствие регрессий

## Известные проблемы и ограничения

### Windows

- Требуются права администратора для создания задач планировщика
- Пути должны использовать обратный слеш или быть экранированными

### Git

- Операция `git gc` может занимать длительное время на больших репозиториях
- При прерывании `git gc` могут создаваться garbage файлы

### EDT

- Workspace должен быть закрыт перед обслуживанием
- Первый запуск после очистки может занять 2-5 минут (индексация)

### 1С

- База должна быть закрыта во всех сеансах
- Требуется установленная платформа 1С

## Дополнительные ресурсы

- [Python Documentation](https://docs.python.org/3/)
- [pytest Documentation](https://docs.pytest.org/)
- [Git Documentation](https://git-scm.com/doc)
- [1С:EDT Documentation](https://its.1c.ru/db/edtdoc)

## Контакты

По вопросам разработки:
- GitHub Issues: https://github.com/yourusername/1C-Sweeper/issues
- Email: developer@example.com


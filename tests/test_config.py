import os
import pytest
from unittest.mock import patch
from api.config import Config


class TestConfig:
    def test_config_loading(self):
        """Тест загрузки конфигурации"""
        assert Config.SECRET_KEY is not None
        assert isinstance(Config.DB_CONFIG, dict)
        assert 'host' in Config.DB_CONFIG
        assert 'port' in Config.DB_CONFIG

    @patch.dict(os.environ, {
        'SECRET_KEY': 'test_key',
        'DB_HOST': 'test_host',
        'DB_PORT': '1234',
        'DB_NAME': 'test_db',
        'DB_USER': 'test_user',
        'DB_PASSWORD': 'test_pass'
    })
    def test_config_with_mock_env(self):
        """Тест конфигурации с мокнутыми переменными окружения"""
        import importlib
        import api.config
        importlib.reload(api.config)

        from api.config import Config as NewConfig

        assert NewConfig.SECRET_KEY == 'test_key'
        assert NewConfig.DB_CONFIG['host'] == 'test_host'
        assert NewConfig.DB_CONFIG['port'] == 1234
        assert NewConfig.DB_CONFIG['database'] == 'test_db'
        assert NewConfig.DB_CONFIG['user'] == 'test_user'
        assert NewConfig.DB_CONFIG['password'] == 'test_pass'
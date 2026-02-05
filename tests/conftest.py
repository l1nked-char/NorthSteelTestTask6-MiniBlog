import os
import sys
from unittest.mock import AsyncMock

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

os.environ['SECRET_KEY'] = 'test_secret_key_for_testing_only'
os.environ['DB_HOST'] = 'localhost'
os.environ['DB_PORT'] = '5432'
os.environ['DB_NAME'] = 'test_db'
os.environ['DB_USER'] = 'test_user'
os.environ['DB_PASSWORD'] = 'test_password'


@pytest.fixture(autouse=True)
def setup_test_environment():
    """Настройка тестового окружения"""
    old_env = {}
    for key in ['SECRET_KEY', 'DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASSWORD']:
        if key in os.environ:
            old_env[key] = os.environ[key]

    os.environ['SECRET_KEY'] = 'test_secret_key_for_testing_only'
    os.environ['DB_HOST'] = 'localhost'
    os.environ['DB_PORT'] = '5432'
    os.environ['DB_NAME'] = 'test_db'
    os.environ['DB_USER'] = 'test_user'
    os.environ['DB_PASSWORD'] = 'test_password'

    yield

    for key, value in old_env.items():
        os.environ[key] = value

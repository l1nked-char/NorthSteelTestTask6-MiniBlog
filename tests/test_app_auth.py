from unittest.mock import patch, AsyncMock, MagicMock
from fastapi.testclient import TestClient
from api.app import app
from fastapi import HTTPException, status
import psycopg2

client = TestClient(app)


class TestAuthEndpoints:
    @patch('api.app.call_func')
    def test_register_user_success(self, mock_call_func):
        """Тест успешной регистрации пользователя"""
        mock_call_func.return_value = {
            "user_id": 1,
            "role": "user"
        }

        response = client.post(
            "/auth/register",
            data={"username": "newuser", "password": "password123"}
        )

        assert response.status_code == 201
        assert "access_token" in response.json()
        mock_call_func.assert_called_once_with(
            "register_user", "newuser", "password123"
        )

    @patch('api.app.call_func')
    def test_register_user_failure(self, mock_call_func):
        """Тест неудачной регистрации"""
        mock_call_func.side_effect = Exception("User exists")

        response = client.post(
            "/auth/register",
            data={"username": "existing", "password": "password123"}
        )

        assert response.status_code == 400 or response.status_code == 500

    @patch('api.app.call_func')
    def test_login_user_success(self, mock_call_func):
        """Тест успешного логина"""
        mock_call_func.return_value = {
            "user_id": 1,
            "role": "user"
        }

        response = client.post(
            "/auth/login",
            data={"username": "test", "password": "password123"}
        )

        assert response.status_code == 200
        assert "access_token" in response.json()

    @patch('api.app.call_func')
    def test_login_user_failure(self, mock_call_func):
        """Тест неудачного логина"""

        error = psycopg2.Error("Invalid credentials")
        mock_call_func.side_effect = error

        response = client.post(
            "/auth/login",
            data={"username": "test", "password": "wrong"}
        )

        assert response.status_code == 401


class TestTokenAuth:
    def create_test_token(self, user_id=1, role="user"):
        """Создание тестового JWT токена"""
        from datetime import datetime, timedelta
        from jose import jwt
        from api.config import Config

        data = {
            "user_id": user_id,
            "role": role,
            "sub": "testuser",
            "exp": datetime.now() + timedelta(minutes=30),
            "iat": datetime.now()
        }
        return jwt.encode(data, Config.SECRET_KEY, algorithm="HS256")

    @patch('api.app.call_func')
    def test_protected_endpoint_with_valid_token(self, mock_call_func):
        """Тест защищенного endpoint с валидным токеном"""
        token = self.create_test_token()
        mock_call_func.return_value = {"posts": []}

        response = client.get(
            "/users/me/posts",
            headers={"Authorization": f"Bearer {token}"}
        )

        assert response.status_code == 200

    def test_protected_endpoint_without_token(self):
        """Тест защищенного endpoint без токена"""
        response = client.get("/users/me/posts")
        assert response.status_code == 401
import pytest
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
from api.app import app

client = TestClient(app)


class TestCommentEndpoints:
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
    def test_get_post_comments(self, mock_call_func):
        """Тест получения комментариев к посту"""
        mock_call_func.return_value = []

        response = client.get("/posts/1/comments?skip=0&limit=10")

        assert response.status_code == 200

    @patch('api.app.call_func')
    def test_create_comment(self, mock_call_func):
        """Тест создания комментария"""
        token = self.create_test_token()
        mock_call_func.return_value = {
            "comment_id": 1,
            "content": "Test comment"
        }

        response = client.post(
            "/posts/1/comments",
            headers={"Authorization": f"Bearer {token}"},
            json={"content": "Test comment", "is_private": False}
        )

        assert response.status_code == 201

    @patch('api.app.call_func')
    def test_update_comment(self, mock_call_func):
        """Тест обновления комментария"""
        token = self.create_test_token()
        mock_call_func.return_value = {
            "comment_id": 1,
            "content": "Updated comment"
        }

        response = client.patch(
            "/posts/1/comments/1",
            headers={"Authorization": f"Bearer {token}"},
            json={"content": "Updated comment"}
        )

        assert response.status_code == 200

    @patch('api.app.call_func')
    def test_change_comment_status_as_moderator(self, mock_call_func):
        """Тест изменения статуса комментария как модератор"""
        token = self.create_test_token(role="moderator")
        mock_call_func.return_value = {
            "comment_id": 1,
            "status": "PUBLISHED"
        }

        response = client.patch(
            "/posts/1/comments/1/change-status",
            headers={"Authorization": f"Bearer {token}"},
            json={"status": "PUBLISHED"}
        )

        assert response.status_code == 200
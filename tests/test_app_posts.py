import pytest
from unittest.mock import patch, AsyncMock, MagicMock
from fastapi.testclient import TestClient
from api.app import app

client = TestClient(app)


class TestPostEndpoints:
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
    def test_get_all_posts_unauthorized(self, mock_call_func):
        """Тест получения постов без авторизации"""
        mock_call_func.return_value = []

        response = client.get("/posts?skip=0&limit=10")

        assert response.status_code == 200
        mock_call_func.assert_called_once_with(
            "get_all_posts", None, 0, 10, 'PUBLISHED'
        )

    @patch('api.app.call_func')
    def test_get_all_posts_authorized(self, mock_call_func):
        """Тест получения постов с авторизацией"""
        token = self.create_test_token()
        mock_call_func.return_value = []

        response = client.get(
            "/posts?skip=0&limit=10&status_filter=DRAFT",
            headers={"Authorization": f"Bearer {token}"}
        )

        assert response.status_code == 200

    @patch('api.app.call_func')
    def test_create_post_success(self, mock_call_func):
        """Тест создания поста"""
        token = self.create_test_token()
        mock_call_func.return_value = {
            "post_id": 1,
            "title": "Test",
            "content": "Content"
        }

        response = client.post(
            "/posts",
            headers={"Authorization": f"Bearer {token}"},
            json={"title": "Test", "content": "Content"}
        )

        assert response.status_code == 201
        assert "post" in response.json()

    @patch('api.app.call_func')
    def test_get_post_published(self, mock_call_func):
        """Тест получения опубликованного поста"""
        mock_call_func.return_value = {
            "post_id": 1,
            "title": "Test",
            "status": "PUBLISHED"
        }

        response = client.get("/posts/1")

        assert response.status_code == 200

    @patch('api.app.call_func')
    @patch('api.app.check_post_author')
    @patch('api.app.check_user_moderator')
    def test_get_post_draft_as_author(
            self, mock_check_moderator, mock_check_author, mock_call_func
    ):
        """Тест получения черновика как автор"""
        token = self.create_test_token()
        mock_call_func.return_value = {
            "post_id": 1,
            "status": "DRAFT"
        }
        mock_check_author.return_value = True
        mock_check_moderator.return_value = False

        response = client.get(
            "/posts/1",
            headers={"Authorization": f"Bearer {token}"}
        )

        assert response.status_code == 200

    @patch('api.app.call_func')
    @patch('api.app.check_post_author')
    @patch('api.app.check_user_moderator')
    def test_update_post_as_author(
            self, mock_check_moderator, mock_check_author, mock_call_func
    ):
        """Тест обновления поста как автор"""
        token = self.create_test_token()
        mock_check_author.return_value = True
        mock_call_func.return_value = {
            "post_id": 1,
            "title": "Updated",
            "content": "Updated content"
        }

        response = client.patch(
            "/posts/1",
            headers={"Authorization": f"Bearer {token}"},
            json={"title": "Updated", "content": "Updated content"}
        )

        assert response.status_code == 200

    @patch('api.app.call_func')
    def test_submit_post_for_review(self, mock_call_func):
        """Тест отправки поста на проверку"""
        token = self.create_test_token()
        mock_call_func.return_value = {
            "post_id": 1,
            "status": "PENDING"
        }

        response = client.patch(
            "/posts/1/submit",
            headers={"Authorization": f"Bearer {token}"}
        )

        assert response.status_code == 200

    @patch('api.app.call_func')
    def test_publish_post_as_moderator(self, mock_call_func):
        """Тест публикации поста как модератор"""
        token = self.create_test_token(user_id=2, role="moderator")
        mock_call_func.return_value = {
            "post_id": 1,
            "status": "PUBLISHED"
        }

        response = client.patch(
            "/posts/1/publish",
            headers={"Authorization": f"Bearer {token}"}
        )

        assert response.status_code == 200
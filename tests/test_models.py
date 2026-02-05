import pytest
from datetime import datetime
from api.models import (
    PostCreate, PostUpdate, CommentCreate,
    CommentStatusUpdate, UserCreate, ChangeUserPassword,
    UserResponse, PostResponse, CommentResponse
)


class TestPostModels:
    def test_post_create_valid(self):
        """Тест создания валидного поста"""
        post = PostCreate(
            title="Test Title",
            content="Test content"
        )

        assert post.title == "Test Title"
        assert post.content == "Test content"

    def test_post_create_empty_title(self):
        """Тест создания поста с пустым заголовком"""
        with pytest.raises(ValueError) as exc_info:
            PostCreate(title="   ", content="Test content")

        assert "Title cannot be empty" in str(exc_info.value)

    def test_post_update_partial(self):
        """Тест частичного обновления поста"""
        post_update = PostUpdate(content="Updated content")

        assert post_update.content == "Updated content"
        assert post_update.title is None

    def test_post_update_empty_title(self):
        """Тест обновления с пустым заголовком"""
        with pytest.raises(ValueError) as exc_info:
            PostUpdate(title="   ")

        assert "Title cannot be empty" in str(exc_info.value)


class TestCommentModels:
    def test_comment_create_valid(self):
        """Тест создания комментария"""
        comment = CommentCreate(
            content="Test comment",
            is_private=True
        )

        assert comment.content == "Test comment"
        assert comment.is_private is True

    def test_comment_status_update_valid(self):
        """Тест обновления статуса комментария"""
        status_update = CommentStatusUpdate(status="PUBLISHED")
        assert status_update.status == "PUBLISHED"

    def test_comment_status_update_invalid(self):
        """Тест невалидного статуса комментария"""
        with pytest.raises(ValueError) as exc_info:
            CommentStatusUpdate(status="INVALID_STATUS")


class TestUserModels:
    def test_user_create_valid(self):
        """Тест создания пользователя"""
        user = UserCreate(
            username="testuser",
            password="password123"
        )

        assert user.username == "testuser"
        assert user.password == "password123"

    def test_change_password(self):
        """Тест изменения пароля"""
        change_pwd = ChangeUserPassword(
            old_password="old123",
            new_password="new456"
        )

        assert change_pwd.old_password == "old123"
        assert change_pwd.new_password == "new456"


class TestResponseModels:
    def test_user_response(self):
        """Тест модели ответа пользователя"""
        user_response = UserResponse(
            user_id=1,
            username="testuser",
            role="user",
            is_banned=False
        )

        assert user_response.user_id == 1
        assert user_response.username == "testuser"

    def test_post_response(self):
        """Тест модели ответа поста"""
        now = datetime.now()
        post_response = PostResponse(
            post_id=1,
            author_id=1,
            title="Test",
            content="Content",
            created_at=now,
            updated_at=now,
            status="PUBLISHED"
        )

        assert post_response.post_id == 1
        assert post_response.status == "PUBLISHED"

    def test_comment_response(self):
        """Тест модели ответа комментария"""
        now = datetime.now()
        comment_response = CommentResponse(
            comment_id=1,
            post_id=1,
            author_id=1,
            content="Comment",
            created_at=now,
            updated_at=now,
            status="PUBLISHED"
        )

        assert comment_response.comment_id == 1
        assert comment_response.post_id == 1
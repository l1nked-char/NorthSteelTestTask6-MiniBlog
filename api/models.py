from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field, validator


# Модели для запросов
class PostCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)
    content: str = Field(..., min_length=1)

    @validator('title')
    def title_not_empty(cls, v):
        if not v.strip():
            raise ValueError('Title cannot be empty')
        return v.strip()


class PostUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=255)
    content: Optional[str] = Field(None, min_length=1)

    @validator('title')
    def title_not_empty(cls, v):
        if v is not None and not v.strip():
            raise ValueError('Title cannot be empty')
        return v.strip() if v else v


class CommentCreate(BaseModel):
    content: str = Field(..., min_length=1, max_length=2000)
    is_private: bool = Field(False, description="Приватный комментарий виден только автору поста и модерации")

class CommentUpdate(BaseModel):
    content: str = Field(..., min_length=1, max_length=2000)

class CommentStatusUpdate(BaseModel):
    status: str = Field(..., pattern="^(PENDING|PUBLISHED|DELETED)$")


class UserCreate(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=6)

class ChangeUserPassword(BaseModel):
    old_password: str = Field(..., min_length=6)
    new_password: str = Field(..., min_length=6)


# Модели для ответов
class UserResponse(BaseModel):
    user_id: int
    username: str
    role: str
    is_banned: bool

    class Config:
        from_attributes = True


class PostResponse(BaseModel):
    post_id: int
    author_id: int
    title: str
    content: str
    created_at: datetime
    updated_at: datetime
    status: str

    class Config:
        from_attributes = True


class CommentResponse(BaseModel):
    comment_id: int
    post_id: int
    author_id: int
    content: str
    created_at: datetime
    updated_at: datetime
    status: str

    class Config:
        from_attributes = True
from datetime import timedelta, datetime

import psycopg2
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from api.queries import call_func
from fastapi.params import Depends
from fastapi import FastAPI, HTTPException, status, Path, Query
from typing import Optional
from api.models import PostCreate, PostUpdate, CommentCreate, CommentUpdate, ChangeUserPassword
from jose import jwt, JWTError
from api.config import Config


SECRET_KEY = Config.SECRET_KEY
ACCESS_TOKEN_EXPIRE_MINUTES = 30
ALGORITHM = "HS256"

oauth_scheme_optional = OAuth2PasswordBearer(tokenUrl="/auth/login", auto_error=False)
oauth_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login", auto_error=True)


app = FastAPI()


# токены и контроль доступа

async def check_post_author(post_id: int, current_user: dict):
    """Проверяет, является ли пользователь автором поста"""
    try:
        result = await call_func("is_post_author", post_id, current_user["user_id"])
        return result
    except Exception:
        return False


async def check_user_moderator(current_user: dict):
    """Проверяет, является ли пользователь модератором"""
    try:
        result = await call_func("is_user_moderator", current_user["user_id"])
        return result
    except Exception:
        return False


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None): # создание jwt-токена
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now() + expires_delta
    else:
        expire = datetime.now() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire, "iat": datetime.now()})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


async def get_current_user(token: str = Depends(oauth_scheme)): # проверка токена
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Не удалось подтвердить учетные данные",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("user_id")
        role: str = payload.get("role")
        if user_id is None or role is None or not await call_func("check_user_role", user_id, role):
            raise credentials_exception
        return {"user_id": user_id, "role": role}
    except JWTError:
        raise credentials_exception
    except Exception as error:
        print(error)
        raise credentials_exception

async def get_current_user_optional(token: Optional[str] = Depends(oauth_scheme_optional)) -> Optional[dict]:
    """Возвращает пользователя если токен валиден, иначе None"""
    if token is None:
        return None

    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("user_id")
        role: str = payload.get("role")

        if user_id is None or role is None or not await call_func("check_user_role", user_id, role):
            return None

        return {"user_id": user_id, "role": role}
    except JWTError:
        return None
    except Exception as error:
        print(f"Error in get_current_user_optional: {error}")
        return None

@app.post("/auth/register") # ++++++++++++++++++++++
async def register_user(new_user: OAuth2PasswordRequestForm = Depends()):
    try:
        response_tuple: dict = await call_func(
            "register_user",
            new_user.username,
            new_user.password
        )

        access_token = create_access_token({
            "user_id": response_tuple["user_id"],
            "role": response_tuple["role"],
            "sub": new_user.username
        })

        return JSONResponse(
            status_code=201,
            content={
                "access_token": access_token,
                "token_type": "bearer",
                "status": "success",
                "expires_in": ACCESS_TOKEN_EXPIRE_MINUTES * 60
            }
        )
    except psycopg2.Error as error:
        return JSONResponse(
            status_code=400,
            content={"message": str(error), "status": "failed"}
        )
    except Exception as error:
        print(str(error))
        return JSONResponse(
            status_code=500,
            content={"message": "Произошла непредвиденная ошибка!", "status": "failed"}
        )

@app.post("/auth/login") # ++++++++++++++++++++++
async def login_user(user_data: OAuth2PasswordRequestForm = Depends()):
    try:
        response_tuple: dict = await call_func(
            "login_user",
            user_data.username,
            user_data.password
        )

        access_token = create_access_token({
            "user_id": response_tuple["user_id"],
            "role": response_tuple["role"],
            "sub": user_data.username
        })

        return JSONResponse(
            status_code=200,
            content={
                "access_token": access_token,
                "token_type": "bearer",
                "status": "success",
                "expires_in": ACCESS_TOKEN_EXPIRE_MINUTES * 60
            }
        )
    except psycopg2.Error as error:
        return JSONResponse(
            status_code=401,
            content={"message": str(error), "status": "failed"}
        )
    except Exception as error:
        print(str(error))
        return JSONResponse(
            status_code=500,
            content={"message": "Произошла непредвиденная ошибка!", "status": "failed"}
        )

@app.post("/auth/reset-password")
async def change_user_password(change_password: ChangeUserPassword, current_user: dict = Depends(get_current_user)): # смена пароля
    try:
        is_changed: bool = await call_func(
            "change_password",
            current_user["role"],
            current_user["user_id"],
            change_password.old_password,
            change_password.new_password
        )

        if is_changed:
            return JSONResponse(
                status_code=200,
                content={"message": "Пароль успешно изменён", "status": "success"}
            )
        else:
            return JSONResponse(
                status_code=400,
                content={"message": "Не удалось изменить пароль", "status": "failed"}
            )
    except psycopg2.Error as error:
        return JSONResponse(
            status_code=400,
            content={"message": str(error), "status": "failed"}
        )
    except Exception as error:
        print(str(error))
        return JSONResponse(
            status_code=500,
            content={"message": "Ошибка обработки данных!", "status": "failed"}
        )


# управление постами
@app.get("/posts", response_model=dict) # ++++++++++++++++++++++
async def get_all_posts(
        skip: int = Query(0, ge=0),
        limit: int = Query(10, ge=1, le=30),
        status_filter: Optional[str] = Query('PUBLISHED', pattern="^(DRAFT|PENDING|PUBLISHED|DELETED)$"),
        current_user: Optional[dict] = Depends(get_current_user_optional)
):
    """
    Получение всех постов с учетом прав доступа:
    - Авторизованные пользователи: видят опубликованные посты + свои посты
    - Модераторы: видят все посты DRAFT других пользователей
    """
    try:
        user_id = current_user.get("user_id") if current_user else None

        if not user_id:
            status_filter = 'PUBLISHED'

        post_data = await call_func("get_all_posts", user_id, skip, limit, status_filter)

        return {"posts": post_data}

    except psycopg2.Error as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error)
        )
    except Exception as error:
        print(f"Error in get_all_posts: {error}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )


@app.post("/posts", status_code=status.HTTP_201_CREATED, response_model=dict) # ++++++++++++++++++++++
async def create_post(
        post: PostCreate,
        current_user: dict = Depends(get_current_user)
):
    """
    Создание нового поста.
    Требуется авторизация.
    Пост создается со статусом DRAFT.
    """
    try:
        author_id = current_user["user_id"]
        post_data = await call_func(
            "create_post",
            post.title,
            post.content,
            author_id
        )

        return {"post": post_data}

    except HTTPException:
        raise
    except psycopg2.Error as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error)
        )
    except Exception as error:
        print(f"Error in create_post: {error}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )


@app.get("/posts/{post_id}", response_model=dict) # ++++++++++++++++++++++
async def get_post(
        post_id: int = Path(..., gt=0),
        current_user: Optional[dict] = Depends(get_current_user_optional)
):
    """
    Получение поста по ID.
    Публичные посты: доступны всем (включая неавторизованных)
    Черновики: доступны только автору
    На проверке: доступны только модераторам
    """
    try:
        user_id = current_user.get("user_id") if current_user else None
        post_data = await call_func("get_post", post_id, user_id)

        if not post_data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Not found"
            )

        post_status = post_data.get("status")

        if post_status == "PUBLISHED":
            return {"message": post_data}

        elif post_status == "DELETED":
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Post not found"
            )

        else:
            if not user_id:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Authentication required to view this post"
                )

            is_author = await check_post_author(post_id, current_user)
            is_moderator = await check_user_moderator(current_user)

            if ((post_status == "DRAFT" and not is_author) or
                (post_status == "PENDING" and not is_author and not is_moderator)):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No permission to view this post"
                )

            return {"post": post_data}

    except HTTPException:
        raise
    except psycopg2.Error as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error)
        )
    except Exception as error:
        print(f"Error in get_post: {error}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )


@app.patch("/posts/{post_id}", response_model=dict) # ++++++++++++++++++++++
async def edit_post(
        post_id: int = Path(..., gt=0),
        post_update: PostUpdate = None,
        current_user: dict = Depends(get_current_user)
):
    """
    Редактирование поста.
    Требуется авторизация.
    Все пользователи могут редактировать только свои посты, кроме DELETED
    """
    try:
        if post_update is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No update data provided"
            )

        update_data = post_update.dict(exclude_unset=True)
        if not update_data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No fields to update"
            )

        is_author = await check_post_author(post_id, current_user)

        if not is_author:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No permission to edit post"
            )

        if is_author:
            post_data = await call_func("get_post", post_id, current_user["user_id"])
            if post_data.get("status") == "DELETED":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="No permission to edit post"
                )

        post_data = await call_func(
            "edit_post",
            current_user["user_id"],
            post_id,
            update_data.get('title'),
            update_data.get('content')
        )

        return {"post": post_data}

    except HTTPException:
        raise
    except psycopg2.Error as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error)
        )
    except Exception as error:
        print(f"Error in edit_post: {error}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )


@app.delete("/posts/{post_id}", status_code=status.HTTP_204_NO_CONTENT) # ++++++++++++++++++++++
async def delete_post(
        post_id: int = Path(..., gt=0),
        current_user: dict = Depends(get_current_user)
):
    """
    Удаление поста.
    Требуется авторизация.
    Пользователь может удалять только свои посты, кроме DELETED
    """
    try:

        await call_func("delete_post", post_id, current_user["user_id"])

        return None

    except HTTPException:
        raise
    except psycopg2.Error as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error)
        )
    except Exception as error:
        print(f"Ошибка: {error}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )


@app.patch("/posts/{post_id}/submit", response_model=dict) # ++++++++++++++++++++++
async def submit_for_review(
        post_id: int = Path(..., gt=0),
        current_user: dict = Depends(get_current_user)
):
    """
    Отправка поста на проверку (DRAFT -> PENDING).
    Только автор может отправить свой пост на проверку.
    """
    try:
        is_author = await check_post_author(post_id, current_user)
        if not is_author:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Только автор может отправить статью на проверку"
            )

        post_data = await call_func("submit_for_review", post_id, current_user["user_id"])

        return {"post": post_data}

    except HTTPException:
        raise
    except psycopg2.Error as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error)
        )
    except Exception as error:
        print(f"Ошибка: {error}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )


@app.patch("/posts/{post_id}/publish", response_model=dict) # +++++++++++++++
async def publish_post(
        post_id: int = Path(..., gt=0),
        current_user: dict = Depends(get_current_user)
):
    """
    Публикация поста.
    Только модератор может публиковать посты.
    Автор не может самостоятельно публиковать свои посты.
    """
    try:
        is_moderator = await check_user_moderator(current_user)
        if not is_moderator:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Только модераторы могут публиковать статьи"
            )

        # Публикуем пост
        post_data = await call_func("publish_post", post_id, current_user["user_id"])

        if 'error' in post_data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=post_data['error']
            )

        return {"post": post_data}

    except HTTPException:
        raise
    except psycopg2.Error as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error)
        )
    except Exception as error:
        print(f"Error in publish_post: {error}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )


# управление комментариями

@app.get("/posts/{post_id}/comments", response_model=dict)
async def get_post_comments(
        post_id: int = Path(..., gt=0),
        skip: int = Query(0, ge=0),
        limit: int = Query(10, ge=1, le=100),
        current_user: Optional[dict] = Depends(get_current_user)
):
    """
    Получение комментариев к посту.
    - Публичные посты: все видят опубликованные комментарии
    - Неопубликованные комментарии видят только их авторы и модерация
    """
    try:
        comments = await call_func(
            "get_post_comments",
            post_id,
            current_user["user_id"],
            skip,
            limit
        )

        return comments

    except HTTPException:
        raise
    except psycopg2.Error as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error)
        )
    except Exception as error:
        print(f"Error in get_post_comments: {error}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@app.post("/posts/{post_id}/comments", status_code=status.HTTP_201_CREATED, response_model=dict)
async def create_comment(
        post_id: int = Path(..., gt=0),
        comment: CommentCreate = None,
        current_user: dict = Depends(get_current_user)
):
    """
    Создание комментария к посту.
    Требуется авторизация.
    """
    try:
        if not current_user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication required"
            )

        if comment is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Comment data required"
            )

        post_data = await call_func("get_post", post_id, current_user["user_id"])
        if not post_data:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Нет прав для комментирования этого поста"
            )

        author_id = current_user["user_id"]
        comment_data = await call_func(
            "create_comment",
            post_id,
            comment.content,
            author_id
        )

        return {"comment": comment_data}

    except HTTPException:
        raise
    except psycopg2.Error as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error)
        )
    except Exception as error:
        print(f"Error in create_comment: {error}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@app.patch("posts/{post_id}/comments/{comment_id}", response_model=dict)
async def update_comment(
        comment_id: int = Path(..., gt=0),
        comment_update: CommentUpdate = None
):
    update_data = comment_update.dict()
    comment_data = await call_func("update_comment", comment_id, update_data)
    return comment_data

@app.patch("posts/{post_id}/comments/{comment_id}/change-status", response_model=dict) # для модераторов
async def change_comment_status(
        comment_id: int = Path(..., gt=0),
        comment_update: CommentUpdate = None
):
    update_data = comment_update.dict()
    comment_data = await call_func("update_comment", comment_id, update_data)
    return comment_data

@app.delete("posts/{post_id}/comments/{comment_id}", response_model=dict)
async def delete_comment(
        comment_id: int = Path(..., gt=0),
        comment_update: CommentUpdate = None
):
    update_data = comment_update.dict()
    comment_data = await call_func("update_comment", comment_id, update_data)
    return comment_data


# управление пользователями
@app.get("/users/me/posts")
async def get_user_posts(current_user: dict = Depends(get_current_user)):
    user_id = current_user["user_id"]
    post_data: dict = await call_func("get_user_comments", user_id)
    return post_data

@app.get("/users/me/comments")
async def get_user_comments(current_user: dict = Depends(get_current_user)):
    user_id = current_user["user_id"]
    post_data: dict = await call_func("get_user_comments", user_id)
    return post_data


from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

# Настройка CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Глобальная обработка ошибок валидации
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request, exc):
    errors = []
    for error in exc.errors():
        errors.append({
            "loc": error["loc"],
            "msg": error["msg"],
            "type": error["type"]
        })
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={"detail": errors},
    )

@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc):
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail},
    )

@app.exception_handler(Exception)
async def generic_exception_handler(request, exc):
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "Internal server error"},
    )

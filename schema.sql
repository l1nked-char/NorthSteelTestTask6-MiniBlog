-- DROP SCHEMA public;

CREATE SCHEMA public AUTHORIZATION postgres;

-- DROP TYPE public."entity_status";

CREATE TYPE public."entity_status" AS ENUM (
	'DRAFT',
	'ARCHIVED',
	'PUBLISHED',
	'PENDING',
	'DELETED');

-- DROP TYPE public."user_role";

CREATE TYPE public."user_role" AS ENUM (
	'user',
	'moderator');

-- DROP SEQUENCE public.comments_comment_id_seq;

CREATE SEQUENCE public.comments_comment_id_seq
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 2147483647
	START 1
	CACHE 1
	NO CYCLE;

-- Permissions

ALTER SEQUENCE public.comments_comment_id_seq OWNER TO postgres;
GRANT ALL ON SEQUENCE public.comments_comment_id_seq TO postgres;

-- DROP SEQUENCE public.posts_post_id_seq;

CREATE SEQUENCE public.posts_post_id_seq
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 2147483647
	START 1
	CACHE 1
	NO CYCLE;

-- Permissions

ALTER SEQUENCE public.posts_post_id_seq OWNER TO postgres;
GRANT ALL ON SEQUENCE public.posts_post_id_seq TO postgres;

-- DROP SEQUENCE public.users_user_id_seq;

CREATE SEQUENCE public.users_user_id_seq
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 2147483647
	START 1
	CACHE 1
	NO CYCLE;

-- Permissions

ALTER SEQUENCE public.users_user_id_seq OWNER TO postgres;
GRANT ALL ON SEQUENCE public.users_user_id_seq TO postgres;
-- public.users определение

-- Drop table

-- DROP TABLE public.users;

CREATE TABLE public.users ( user_id int4 GENERATED ALWAYS AS IDENTITY( INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 START 1 CACHE 1 NO CYCLE) NOT NULL, username varchar NOT NULL, "role" public."user_role" NOT NULL, encrypted_password varchar NOT NULL, CONSTRAINT users_pk PRIMARY KEY (user_id), CONSTRAINT users_username_unique UNIQUE (username));

-- Permissions

ALTER TABLE public.users OWNER TO postgres;
GRANT UPDATE, INSERT, SELECT, TRUNCATE, TRIGGER, REFERENCES, DELETE ON TABLE public.users TO postgres;
GRANT UPDATE, INSERT, SELECT ON TABLE public.users TO api_user;


-- public.posts определение

-- Drop table

-- DROP TABLE public.posts;

CREATE TABLE public.posts ( post_id int4 GENERATED ALWAYS AS IDENTITY( INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 START 1 CACHE 1 NO CYCLE) NOT NULL, user_id int4 NOT NULL, title varchar NOT NULL, "content" text NOT NULL, created_at timestamp NOT NULL, updated_at timestamp NOT NULL, status public."entity_status" NOT NULL, CONSTRAINT posts_pk PRIMARY KEY (post_id), CONSTRAINT posts_users_fk FOREIGN KEY (user_id) REFERENCES public.users(user_id));

-- Permissions

ALTER TABLE public.posts OWNER TO postgres;
GRANT UPDATE, INSERT, SELECT, TRUNCATE, TRIGGER, REFERENCES, DELETE ON TABLE public.posts TO postgres;
GRANT UPDATE, INSERT, SELECT ON TABLE public.posts TO api_user;


-- public."comments" определение

-- Drop table

-- DROP TABLE public."comments";

CREATE TABLE public."comments" ( comment_id int4 GENERATED ALWAYS AS IDENTITY( INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 START 1 CACHE 1 NO CYCLE) NOT NULL, post_id int4 NOT NULL, user_id int4 NOT NULL, "content" text NOT NULL, created_at timestamp NOT NULL, updated_at timestamp NOT NULL, status public."entity_status" NOT NULL, is_private bool NOT NULL, CONSTRAINT comments_pk PRIMARY KEY (comment_id), CONSTRAINT comments_posts_fk FOREIGN KEY (post_id) REFERENCES public.posts(post_id), CONSTRAINT comments_users_fk FOREIGN KEY (user_id) REFERENCES public.users(user_id));

-- Permissions

ALTER TABLE public."comments" OWNER TO postgres;
GRANT UPDATE, INSERT, SELECT, TRUNCATE, TRIGGER, REFERENCES, DELETE ON TABLE public."comments" TO postgres;
GRANT UPDATE, INSERT, SELECT ON TABLE public."comments" TO api_user;



-- DROP FUNCTION public.change_comment_status(int4, int4, varchar, int4);

CREATE OR REPLACE FUNCTION public.change_comment_status(post_id_param integer, comment_id_param integer, new_status_param character varying, current_user_id integer)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    is_moderator_check BOOLEAN;
    comment_record RECORD;
    result_json JSON;
BEGIN
    SELECT is_user_moderator(current_user_id) INTO is_moderator_check;

    IF NOT is_moderator_check THEN
        RAISE EXCEPTION 'Только модератор может менять статус комментария';
    END IF;

    SELECT * INTO comment_record FROM public.comments WHERE comment_id = comment_id_param AND post_id = post_id_param;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Комментарий не найден';
    END IF;

    UPDATE public.comments
    SET
        status = new_status_param::public.entity_status,
        updated_at = NOW()
    WHERE comment_id = comment_id_param;

    SELECT json_build_object(
        'comment_id', c.comment_id,
        'post_id', c.post_id,
        'author_id', c.user_id,
        'content', c.content,
        'created_at', c.created_at,
        'updated_at', c.updated_at,
        'status', c.status,
        'is_private', c.is_private,
        'author_username', u.username
    ) INTO result_json
    FROM public.comments c
    JOIN public.users u ON c.user_id = u.user_id
    WHERE c.comment_id = comment_id_param;

    RETURN result_json;
END;
$function$
;

-- Permissions

ALTER FUNCTION public.change_comment_status(int4, int4, varchar, int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.change_comment_status(int4, int4, varchar, int4) TO postgres;

-- DROP FUNCTION public.change_password(int4, varchar, varchar);

CREATE OR REPLACE FUNCTION public.change_password(user_id_param integer, old_password_param character varying, new_password_param character varying)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    current_password TEXT;
BEGIN
    SELECT encrypted_password
    INTO current_password
    FROM users
    WHERE user_id = user_id_param;

    IF NOT found THEN
        RAISE EXCEPTION 'Пользовтель не найден';
    END IF;
    IF current_password <> old_password_param THEN
        RAISE EXCEPTION 'Неверный старый пароль';
    END IF;
    IF current_password = new_password_param THEN
        RAISE EXCEPTION 'Новый пароль не должен совпадать со старым';
    END IF;

    UPDATE public.users
    SET encrypted_password = new_password_param
    WHERE user_id = user_id_param;

	RETURN TRUE;
END;
$function$
;

-- Permissions

ALTER FUNCTION public.change_password(int4, varchar, varchar) OWNER TO postgres;
GRANT ALL ON FUNCTION public.change_password(int4, varchar, varchar) TO public;
GRANT ALL ON FUNCTION public.change_password(int4, varchar, varchar) TO postgres;
GRANT ALL ON FUNCTION public.change_password(int4, varchar, varchar) TO api_user;

-- DROP FUNCTION public.check_user_role(int4, varchar);

CREATE OR REPLACE FUNCTION public.check_user_role(user_id_param integer, expected_role character varying)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    u_role VARCHAR;
BEGIN
    SELECT public.users."role" INTO u_role
    FROM public.users
    WHERE user_id = user_id_param;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    RETURN u_role::varchar = expected_role::varchar;
END;
$function$
;

-- Permissions

ALTER FUNCTION public.check_user_role(int4, varchar) OWNER TO postgres;
GRANT ALL ON FUNCTION public.check_user_role(int4, varchar) TO public;
GRANT ALL ON FUNCTION public.check_user_role(int4, varchar) TO postgres;
GRANT ALL ON FUNCTION public.check_user_role(int4, varchar) TO api_user;

-- DROP FUNCTION public.create_comment(int4, text, int4, bool);

CREATE OR REPLACE FUNCTION public.create_comment(post_id_param integer, content_param text, author_id_param integer, is_private_param boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    post_record RECORD;
    post_author_id INTEGER;
    post_status VARCHAR;
    is_moderator_check BOOLEAN;
    is_author_of_post BOOLEAN;
    new_comment_id INTEGER;
    comment_status VARCHAR;
    result_json JSON;
BEGIN
    SELECT user_id, status INTO post_author_id, post_status
    FROM public.posts
    WHERE post_id = post_id_param AND status::varchar not in ('DELETED', 'DRAFT');

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Пост не найден';
    END IF;

    SELECT is_user_moderator(author_id_param) INTO is_moderator_check;
    SELECT (post_author_id = author_id_param) INTO is_author_of_post;

	IF post_status = 'PENDING' AND NOT (is_author_of_post OR is_moderator_check) THEN
			RAISE EXCEPTION 'Недостаточно прав для комментирования этого поста';
        is_private_param := TRUE;
    END IF;

    IF is_private_param THEN
        comment_status := 'PUBLISHED';
    ELSE
        comment_status := 'PENDING';
    END IF;

    INSERT INTO public.comments (
        post_id,
        user_id,
        content,
        created_at,
        updated_at,
        status,
        is_private
    ) VALUES (
        post_id_param,
        author_id_param,
        content_param,
        NOW(),
        NOW(),
        comment_status::public.entity_status,
        is_private_param
    ) RETURNING comment_id INTO new_comment_id;

    SELECT json_build_object(
        'comment_id', c.comment_id,
        'post_id', c.post_id,
        'author_id', c.user_id,
        'content', c.content,
        'created_at', c.created_at,
        'updated_at', c.updated_at,
        'status', c.status,
        'is_private', c.is_private,
        'author_username', u.username
    ) INTO result_json
    FROM public.comments c
    JOIN public.users u ON c.user_id = u.user_id
    WHERE c.comment_id = new_comment_id;

    RETURN result_json;

END;
$function$
;

-- Permissions

ALTER FUNCTION public.create_comment(int4, text, int4, bool) OWNER TO postgres;
GRANT ALL ON FUNCTION public.create_comment(int4, text, int4, bool) TO postgres;

-- DROP FUNCTION public.create_post(varchar, text, int4);

CREATE OR REPLACE FUNCTION public.create_post(title_param character varying, content_param text, author_id_param integer)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
	post_id_p INT;
BEGIN
	PERFORM 1 FROM users WHERE user_id = author_id_param;
	IF NOT FOUND THEN
	    RAISE EXCEPTION 'Пользователь не найден';
	ELSE
		INSERT INTO public.posts (
		        user_id,
		        title,
		        "content",
		        created_at,
		        updated_at,
		        status
		    ) VALUES (
		        author_id_param,
		        title_param,
		        content_param,
		        NOW(),
		        NOW(),
		        'DRAFT'::public.entity_status
		    ) RETURNING post_id INTO post_id_p;
	END IF;

	return public.get_post(post_id_p, author_id_param);
END;
$function$
;

-- Permissions

ALTER FUNCTION public.create_post(varchar, text, int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.create_post(varchar, text, int4) TO postgres;

-- DROP FUNCTION public.delete_comment(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.delete_comment(post_id_param integer, comment_id_param integer, current_user_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    is_author_check BOOLEAN;
    is_moderator_check BOOLEAN;
    comment_record RECORD;
BEGIN
    SELECT * INTO comment_record FROM public.comments WHERE post_id = post_id_param AND comment_id = comment_id_param AND status::varchar != 'DELETED';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Комментарий не найден';
    END IF;

    SELECT is_comment_author(comment_id_param, current_user_id) INTO is_author_check;
    SELECT is_user_moderator(current_user_id) INTO is_moderator_check;

    IF NOT is_author_check AND NOT is_moderator_check THEN
        RAISE EXCEPTION 'Нет прав для удаления комментария';
    END IF;

    UPDATE public.comments
    SET status = 'DELETED'::public.entity_status, updated_at = NOW()
    WHERE comment_id = comment_id_param;

END;
$function$
;

-- Permissions

ALTER FUNCTION public.delete_comment(int4, int4, int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.delete_comment(int4, int4, int4) TO postgres;

-- DROP FUNCTION public.delete_post(int4, int4);

CREATE OR REPLACE FUNCTION public.delete_post(post_id_param integer, current_user_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    post_record RECORD;
    is_author_check BOOLEAN;
    is_moderator_check BOOLEAN;
BEGIN
    SELECT * INTO post_record FROM public.posts WHERE post_id = post_id_param;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Статья не найдена';
    END IF;

    SELECT is_post_author(post_id_param, current_user_id) INTO is_author_check;
    SELECT is_user_moderator(current_user_id) INTO is_moderator_check;

    IF is_author_check THEN
        IF post_record.status = 'DELETED' THEN
			RAISE EXCEPTION 'Статья не найдена';
        END IF;
    ELSE
		RAISE EXCEPTION 'Нет прав на удаление';
    END IF;

    UPDATE public.posts
    SET status = 'DELETED', updated_at = NOW()
    WHERE post_id = post_id_param;

    UPDATE public.comments
    SET status = 'DELETED', updated_at = NOW()
    WHERE post_id = post_id_param;

END;
$function$
;

-- Permissions

ALTER FUNCTION public.delete_post(int4, int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.delete_post(int4, int4) TO postgres;

-- DROP FUNCTION public.edit_post(int4, int4, varchar, text);

CREATE OR REPLACE FUNCTION public.edit_post(user_edit_id integer, post_id_param integer, title_param character varying DEFAULT NULL::character varying, content_param text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
BEGIN
	PERFORM 1 FROM posts WHERE post_id = post_id_param;

	IF NOT FOUND THEN
        RAISE EXCEPTION 'Статья не найдена';
    END IF;

	PERFORM 1 FROM posts WHERE post_id = post_id_param AND
	(public.is_post_author(post_id_param, user_edit_id) OR public.is_user_moderator(user_edit_id));

	IF NOT FOUND THEN
        RAISE EXCEPTION 'Недостаточно прав для редактирования статьи';
    END IF;

    UPDATE public.posts
    SET
        title = COALESCE(title_param, title),
        content = COALESCE(content_param, content),
        updated_at = NOW(),
		status = CASE
			        WHEN comment_record.status = 'PUBLISHED' THEN 'PENDING'::public.entity_status
			        ELSE comment_record.status
			    END
    WHERE post_id = post_id_param
    AND status != 'DELETED';

	RETURN public.get_post(post_id_param, user_edit_id);
END;
$function$
;

-- Permissions

ALTER FUNCTION public.edit_post(int4, int4, varchar, text) OWNER TO postgres;
GRANT ALL ON FUNCTION public.edit_post(int4, int4, varchar, text) TO postgres;

-- DROP FUNCTION public.get_all_posts(int4, int4, int4, varchar);

CREATE OR REPLACE FUNCTION public.get_all_posts(user_id_p integer DEFAULT NULL::integer, skip_param integer DEFAULT 0, limit_param integer DEFAULT 10, status_filter character varying DEFAULT 'PUBLISHED'::character varying)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    result_json JSON;
    is_moderator_check BOOLEAN;
BEGIN
    SELECT is_user_moderator(COALESCE(user_id_p, 0)) INTO is_moderator_check;

	IF not is_moderator_check AND status_filter::varchar = 'DELETED' THEN
        RAISE EXCEPTION 'Недостаточно прав для просмотра постов';
    END IF;

	SELECT COALESCE(json_agg(row_to_json(posts)), '[]'::json) INTO result_json
FROM (
    SELECT
        p.post_id,
        p.user_id as author_id,
        p.title,
        p.content,
        p.created_at,
        p.updated_at,
        p.status,
        u.username as author_username
    FROM public.posts p
    JOIN public.users u ON p.user_id = u.user_id
    WHERE
        (
            (user_id_p IS NULL AND p.status::varchar = 'PUBLISHED')
            OR
            (user_id_p IS NOT NULL AND (
                p.status::varchar = 'PUBLISHED' OR
                (p.user_id = user_id_p AND p.status IN ('DRAFT', 'PENDING')) OR
                (is_moderator_check AND p.status::varchar = 'PENDING' AND p.user_id != user_id_p) OR
                (is_moderator_check AND p.status::varchar = 'DELETED')))
        )
        AND (status_filter IS NULL OR p.status::varchar = status_filter)
    ORDER BY p.created_at DESC
    OFFSET skip_param
    LIMIT limit_param
) posts;

    RETURN COALESCE(result_json, '[]'::json);
END;
$function$
;

-- Permissions

ALTER FUNCTION public.get_all_posts(int4, int4, int4, varchar) OWNER TO postgres;
GRANT ALL ON FUNCTION public.get_all_posts(int4, int4, int4, varchar) TO postgres;

-- DROP FUNCTION public.get_pending_comments(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.get_pending_comments(current_user_id integer, skip_param integer DEFAULT 0, limit_param integer DEFAULT 10)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    is_moderator_check BOOLEAN;
    result_json JSON;
BEGIN
    SELECT is_user_moderator(current_user_id) INTO is_moderator_check;

    IF NOT is_moderator_check THEN
        RAISE EXCEPTION 'Нет прав для просмотра этого типа комментариев';
    END IF;

    SELECT COALESCE(json_agg(row_to_json(comments)), '[]'::json) INTO result_json
    FROM (
        SELECT
            c.comment_id,
            c.post_id,
            c.user_id as author_id,
            c.content,
            c.created_at,
            c.updated_at,
            c.status,
            c.is_private,
            u.username as author_username,
            p.title as post_title,
            p.status as post_status,
            p.user_id as post_author_id,
            pu.username as post_author_username
        FROM public.comments c
        JOIN public.users u ON c.user_id = u.user_id
        JOIN public.posts p ON c.post_id = p.post_id
        JOIN public.users pu ON p.user_id = pu.user_id
        WHERE c.status = 'PENDING' AND c.user_id != current_user_id AND p.status != 'DELETED'
        ORDER BY
            c.updated_at ASC
        OFFSET skip_param
        LIMIT limit_param
    ) comments;

    RETURN result_json;
END;
$function$
;

-- Permissions

ALTER FUNCTION public.get_pending_comments(int4, int4, int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.get_pending_comments(int4, int4, int4) TO postgres;

-- DROP FUNCTION public.get_post(int4, int4);

CREATE OR REPLACE FUNCTION public.get_post(post_id_param integer, user_id_p integer DEFAULT NULL::integer)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    result_json JSON;
    is_moderator_check BOOLEAN;
BEGIN
    IF user_id_p IS NULL THEN
        is_moderator_check := FALSE;
    ELSE
        SELECT is_user_moderator(user_id_p) INTO is_moderator_check;
    END IF;

    SELECT json_build_object(
        'post_id', p.post_id,
        'author_id', p.user_id,
        'author_username', u.username,
        'title', p.title,
        'content', p.content,
        'created_at', p.created_at,
        'updated_at', p.updated_at,
        'status', p.status
    ) INTO result_json
    FROM public.posts p
    JOIN public.users u ON p.user_id = u.user_id
    WHERE p.post_id = post_id_param
    AND ((user_id_p IS NULL AND p.status = 'PUBLISHED') OR
         (user_id_p IS NOT NULL AND (
            p.status = 'PUBLISHED' OR
            (p.user_id = user_id_p AND p.status IN ('DRAFT', 'PENDING')) OR
            (is_moderator_check AND p.status = 'PENDING' AND p.user_id != user_id_p) OR
            (is_moderator_check AND p.status = 'DELETED'))));

    RETURN result_json;
END;
$function$
;

-- Permissions

ALTER FUNCTION public.get_post(int4, int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.get_post(int4, int4) TO postgres;

-- DROP FUNCTION public.get_post_comments(int4, int4, int4, int4);

CREATE OR REPLACE FUNCTION public.get_post_comments(post_id_param integer, current_user_id integer DEFAULT NULL::integer, skip_param integer DEFAULT 0, limit_param integer DEFAULT 10)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    post_record RECORD;
    is_moderator_check BOOLEAN;
    is_post_author_check BOOLEAN;
    result_json JSON;
BEGIN
    SELECT * INTO post_record FROM public.posts WHERE post_id = post_id_param AND status NOT IN ('DRAFT', 'DELETED');

    IF NOT FOUND THEN
        RETURN '[]'::json;
    END IF;

    IF current_user_id IS NULL THEN
        is_moderator_check := FALSE;
        is_post_author_check := FALSE;
    ELSE
        SELECT is_user_moderator(current_user_id) INTO is_moderator_check;
        SELECT is_post_author(post_id_param, current_user_id) INTO is_post_author_check;
    END IF;

    SELECT COALESCE(json_agg(row_to_json(comments)), '[]'::json) INTO result_json
            FROM (
                SELECT
                    c.comment_id,
                    c.post_id,
                    c.user_id as author_id,
                    c.content,
                    c.created_at,
                    c.updated_at,
                    c.status,
                    c.is_private,
                    u.username as author_username
                FROM public.comments c
                JOIN public.users u ON c.user_id = u.user_id
                WHERE c.post_id = post_id_param AND c.status::varchar != 'DELETED' AND
						((c.status::varchar = 'PUBLISHED' AND c.is_private = False) OR
						 (c.is_private = True AND (is_moderator_check OR is_post_author_check)) OR
						  c.user_id = current_user_id)
                ORDER BY c.created_at DESC
                OFFSET skip_param
                LIMIT limit_param
            ) comments;

    RETURN COALESCE(result_json, '[]'::json);

END;
$function$
;

-- Permissions

ALTER FUNCTION public.get_post_comments(int4, int4, int4, int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.get_post_comments(int4, int4, int4, int4) TO postgres;

-- DROP FUNCTION public.get_user_comments(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.get_user_comments(current_user_id integer, skip_param integer DEFAULT 0, limit_param integer DEFAULT 10)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    result_json JSON;
BEGIN
    SELECT COALESCE(json_agg(row_to_json(comments)), '[]'::json) INTO result_json
    FROM (
        SELECT
            c.comment_id,
            c.post_id,
            c.user_id as author_id,
            c.content,
            c.created_at,
            c.updated_at,
            c.status as comment_status,
            c.is_private,
            u.username as author_username,
            p.title as post_title,
            p.status as post_status,
            p.user_id as post_author_id,
            pu.username as post_author_username
        FROM public.comments c
        JOIN public.users u ON c.user_id = u.user_id
        JOIN public.posts p ON c.post_id = p.post_id
        JOIN public.users pu ON p.user_id = pu.user_id
        WHERE c.user_id = current_user_id
        AND c.status != 'DELETED'
        AND p.status != 'DELETED'
        ORDER BY c.created_at DESC
		OFFSET skip_param
        LIMIT limit_param
    ) comments;

    RETURN result_json;
END;
$function$
;

-- Permissions

ALTER FUNCTION public.get_user_comments(int4, int4, int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.get_user_comments(int4, int4, int4) TO postgres;

-- DROP FUNCTION public.get_user_posts(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.get_user_posts(current_user_id integer, skip_param integer DEFAULT 0, limit_param integer DEFAULT 10)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    is_author_check BOOLEAN;
    result_json JSON;
BEGIN
    SELECT json_agg(row_to_json(posts)) INTO result_json
    FROM (
        SELECT
            p.post_id,
            p.user_id as author_id,
            p.title,
            p.content,
            p.created_at,
            p.updated_at,
            p.status,
            u.username as author_username
        FROM public.posts p
        JOIN public.users u USING (user_id)
        WHERE p.user_id = current_user_id
        AND p.status != 'DELETED'
        ORDER BY
            CASE p.status
                WHEN 'PENDING' THEN 1
                WHEN 'DRAFT' THEN 2
                WHEN 'PUBLISHED' THEN 3
                ELSE 4
            END,
            p.created_at DESC
		OFFSET skip_param
	    LIMIT limit_param
    ) posts;

    RETURN COALESCE(result_json, '[]'::json);
END;
$function$
;

-- Permissions

ALTER FUNCTION public.get_user_posts(int4, int4, int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.get_user_posts(int4, int4, int4) TO postgres;

-- DROP FUNCTION public.get_user_role(int4);

CREATE OR REPLACE FUNCTION public.get_user_role(user_id_param integer)
 RETURNS user_role
 LANGUAGE plpgsql
AS $function$
DECLARE
    user_role public.user_role;
BEGIN
    SELECT role INTO user_role
    FROM public.users
    WHERE user_id = user_id_param;

    RETURN user_role;
END;
$function$
;

-- Permissions

ALTER FUNCTION public.get_user_role(int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.get_user_role(int4) TO public;
GRANT ALL ON FUNCTION public.get_user_role(int4) TO postgres;
GRANT ALL ON FUNCTION public.get_user_role(int4) TO api_user;

-- DROP FUNCTION public.is_comment_author(int4, int4);

CREATE OR REPLACE FUNCTION public.is_comment_author(comment_id_param integer, user_id_param integer)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    is_author BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM public.comments
        WHERE comment_id = comment_id_param
        AND user_id = user_id_param
    ) INTO is_author;

    RETURN is_author;
END;
$function$
;

-- Permissions

ALTER FUNCTION public.is_comment_author(int4, int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.is_comment_author(int4, int4) TO postgres;

-- DROP FUNCTION public.is_post_author(int4, int4);

CREATE OR REPLACE FUNCTION public.is_post_author(post_id_param integer, user_id_param integer)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    is_author BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM public.posts
        WHERE post_id = post_id_param
        AND user_id = user_id_param
    ) INTO is_author;

    RETURN is_author;
END;
$function$
;

-- Permissions

ALTER FUNCTION public.is_post_author(int4, int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.is_post_author(int4, int4) TO public;
GRANT ALL ON FUNCTION public.is_post_author(int4, int4) TO postgres;
GRANT ALL ON FUNCTION public.is_post_author(int4, int4) TO api_user;

-- DROP FUNCTION public.is_user_moderator(int4);

CREATE OR REPLACE FUNCTION public.is_user_moderator(user_id_param integer)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    is_mod BOOLEAN;
BEGIN
    SELECT (public.users."role" = 'moderator'::public.user_role) INTO is_mod
    FROM public.users
    WHERE user_id = user_id_param;

    RETURN COALESCE(is_mod, FALSE);
END;
$function$
;

-- Permissions

ALTER FUNCTION public.is_user_moderator(int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.is_user_moderator(int4) TO public;
GRANT ALL ON FUNCTION public.is_user_moderator(int4) TO postgres;
GRANT ALL ON FUNCTION public.is_user_moderator(int4) TO api_user;

-- DROP FUNCTION public.login_user(varchar, varchar);

CREATE OR REPLACE FUNCTION public.login_user(username_param character varying, password_param character varying)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    user_record RECORD;
    result_json JSON;
BEGIN
    SELECT
        user_id,
        username,
        role,
        encrypted_password
    INTO user_record
    FROM public.users
    WHERE username = username_param;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Неверное имя пользователя или пароль';
    END IF;

    IF user_record.encrypted_password != password_param THEN
        RAISE EXCEPTION 'Неверное имя пользователя или пароль';
    END IF;

    SELECT json_build_object(
        'user_id', user_record.user_id,
        'role', user_record.role
    ) INTO result_json;

    RETURN result_json;
END;
$function$
;

-- Permissions

ALTER FUNCTION public.login_user(varchar, varchar) OWNER TO postgres;
GRANT ALL ON FUNCTION public.login_user(varchar, varchar) TO public;
GRANT ALL ON FUNCTION public.login_user(varchar, varchar) TO postgres;
GRANT ALL ON FUNCTION public.login_user(varchar, varchar) TO api_user;

-- DROP FUNCTION public.publish_post(int4, int4);

CREATE OR REPLACE FUNCTION public.publish_post(post_id_param integer, current_user_id integer)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    is_moderator_check BOOLEAN;
    result_json JSON;
BEGIN
    SELECT is_user_moderator(current_user_id) INTO is_moderator_check;

    IF NOT is_moderator_check THEN
        RETURN json_build_object('error', 'Only moderators can publish posts');
    END IF;

    UPDATE public.posts
    SET status = 'PUBLISHED', updated_at = NOW()
    WHERE post_id = post_id_param AND status = 'PENDING' AND current_user_id != user_id;

    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Only PENDING posts can be published');
    END IF;

    SELECT get_post(post_id_param) INTO result_json;

    RETURN result_json;
END;
$function$
;

-- Permissions

ALTER FUNCTION public.publish_post(int4, int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.publish_post(int4, int4) TO public;
GRANT ALL ON FUNCTION public.publish_post(int4, int4) TO postgres;
GRANT ALL ON FUNCTION public.publish_post(int4, int4) TO api_user;

-- DROP FUNCTION public.register_user(varchar, varchar);

CREATE OR REPLACE FUNCTION public.register_user(username_param character varying, password_param character varying)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    new_user_id INTEGER;
    user_exists BOOLEAN;
    result_json JSON;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM public.users
        WHERE username = username_param
    ) INTO user_exists;

    IF user_exists THEN
        RAISE EXCEPTION 'Пользователь с таким именем уже существует';
    END IF;

    INSERT INTO public.users (
        username,
        encrypted_password,
        role
    ) VALUES (
        username_param,
        password_param,
        'user'::public.user_role
    ) RETURNING user_id INTO new_user_id;

    SELECT json_build_object(
        'user_id', new_user_id,
        'role', 'user'
    ) INTO result_json;

    RETURN result_json;
END;
$function$
;

-- Permissions

ALTER FUNCTION public.register_user(varchar, varchar) OWNER TO postgres;
GRANT ALL ON FUNCTION public.register_user(varchar, varchar) TO public;
GRANT ALL ON FUNCTION public.register_user(varchar, varchar) TO postgres;
GRANT ALL ON FUNCTION public.register_user(varchar, varchar) TO api_user;

-- DROP FUNCTION public.submit_for_review(int4, int4);

CREATE OR REPLACE FUNCTION public.submit_for_review(post_id_param integer, current_user_id integer)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    post_record RECORD;
    is_author_check BOOLEAN;
    result_json JSON;
BEGIN
    SELECT * INTO post_record FROM public.posts WHERE post_id = post_id_param;

    IF NOT FOUND THEN
		RAISE EXCEPTION 'Пост не найден';
    END IF;

    SELECT is_post_author(post_id_param, current_user_id) INTO is_author_check;

    IF NOT is_author_check THEN
		RAISE EXCEPTION 'Только автор может отправить пост на проверку';
    END IF;

    IF post_record.status != 'DRAFT' THEN
		RAISE EXCEPTION 'На проверку можно отправить только черновики';
    END IF;

    UPDATE public.posts
    SET status = 'PENDING', updated_at = NOW()
    WHERE post_id = post_id_param;

    SELECT get_post(post_id_param, current_user_id) INTO result_json;

    RETURN result_json;
END;
$function$
;

-- Permissions

ALTER FUNCTION public.submit_for_review(int4, int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.submit_for_review(int4, int4) TO public;
GRANT ALL ON FUNCTION public.submit_for_review(int4, int4) TO postgres;
GRANT ALL ON FUNCTION public.submit_for_review(int4, int4) TO api_user;

-- DROP FUNCTION public.update_comment(int4, int4, text, int4);

CREATE OR REPLACE FUNCTION public.update_comment(post_id_param integer, comment_id_param integer, content_param text, current_user_id integer)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    comment_record RECORD;
    is_author_check BOOLEAN;
    result_json JSON;
BEGIN
	SELECT * INTO comment_record FROM public.comments WHERE post_id = post_id_param AND comment_id = comment_id_param AND status::varchar != 'DELETED';

    IF NOT FOUND THEN
		RAISE EXCEPTION 'Комментарий не найден';
    END IF;

    SELECT is_comment_author(comment_id_param, current_user_id) INTO is_author_check;

    IF NOT is_author_check THEN
		RAISE EXCEPTION 'Только автор может редактировать комментарий';
    END IF;

    UPDATE public.comments
    SET
        content = content_param,
        updated_at = NOW(),
        status = CASE
            WHEN comment_record.status::varchar = 'PUBLISHED' and not comment_record.is_private THEN 'PENDING'::public.entity_status
            ELSE comment_record.status
        END
    WHERE comment_id = comment_id_param;

    SELECT json_build_object(
        'comment_id', c.comment_id,
        'post_id', c.post_id,
        'author_id', c.user_id,
        'content', c.content,
        'created_at', c.created_at,
        'updated_at', c.updated_at,
        'status', c.status,
        'is_private', c.is_private,
        'author_username', u.username
    ) INTO result_json
    FROM public.comments c
    JOIN public.users u ON c.user_id = u.user_id
    WHERE c.comment_id = comment_id_param;

    RETURN result_json;

END;
$function$
;

-- Permissions

ALTER FUNCTION public.update_comment(int4, int4, text, int4) OWNER TO postgres;
GRANT ALL ON FUNCTION public.update_comment(int4, int4, text, int4) TO postgres;


-- Permissions

GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO public;
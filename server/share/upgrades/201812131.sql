/*
// Postgres Enterprise Manager
//
// Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
//
// Portions of Postgres Enteprise Manager are derived from pgAgent, which is
// released under the PostgreSQL License.
// Copyright (C) 2002 - 2010 The pgAdmin Development Team
//
*/

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201812131::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS
 'Returns the version number of the PEM schema';

ALTER TABLE pem.user_server_group
    ADD COLUMN deleted boolean NOT NULL DEFAULT false;
DROP FUNCTION pem.rename_server_group(integer, text);
DROP FUNCTION pem.delete_server_group(integer);

GRANT INSERT ON TABLE pem.user_server_group TO pem_user;

CREATE OR REPLACE FUNCTION pem.create_server_group(
    _name text, _uid oid DEFAULT pem.current_user_id()
) RETURNS integer AS
$$
DECLARE
    gid integer;
    hidden bool;
BEGIN
    SELECT s.id, s.hidden INTO gid, hidden FROM pem.user_server_group s WHERE s.name = _name AND uid = _uid;

    IF gid IS NOT NULL THEN
        IF hidden THEN
            UPDATE pem.user_server_group SET hidden = FALSE WHERE id = gid;
        END IF;
        RETURN gid;
    ELSE
        SELECT s.id INTO gid FROM pem.server_group s WHERE s.name = _name;

        IF gid IS NULL THEN
            INSERT INTO pem.server_group(name) VALUES (_name) RETURNING id INTO gid;
        END IF;
        RETURN gid;
    END IF;
END$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.rename_server_group(
    _id integer, _name text,
    _uid oid DEFAULT pem.current_user_id()
)
RETURNS integer AS
$$
DECLARE
    v_gid integer;
    v_deleted bool;
BEGIN
    -- Server group name already exists for the user!
    SELECT s.id INTO v_gid FROM pem.user_server_group s
    WHERE s.name = _name AND s.uid = _uid;

    IF FOUND THEN
        RETURN -2;
    END IF;

    SELECT s.id INTO v_gid FROM pem.server_group s WHERE s.name = _name AND
    NOT EXISTS(
        SELECT g.id FROM pem.user_server_group g
        WHERE g.id = s.id AND g.uid = _uid
    );

    -- Already present!
    IF FOUND THEN
        RETURN -3;
    END IF;

    SELECT s.deleted INTO v_deleted FROM pem.user_server_group s
    WHERE s.id = _id AND s.uid = _uid;

    IF FOUND THEN
        IF v_deleted THEN
            -- Can't change deleted!
            RETURN -1;
        END IF;
        SELECT id INTO v_gid FROM pem.server_group
        WHERE id = _id AND name = _name;

        IF FOUND THEN
            DELETE FROM pem.user_server_group WHERE id = _id AND uid = _uid;
        ELSE
            UPDATE pem.user_server_group SET name = _name WHERE id = _id;
        END IF;
        RETURN 0;
    END IF;

    INSERT INTO pem.user_server_group (id, name, uid) VALUES (_id, _name, _uid);
    RETURN 0;

END$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.change_server_group(
    _old integer, _aid integer, _sid integer, _uid integer
) RETURNS integer AS $$
DECLARE
    v_cnt integer;
    v_user text;
BEGIN

    SELECT rolname into v_user FROM pg_roles WHERE oid = _uid;

    EXECUTE $SQL$
WITH update_agent_options AS (
    UPDATE pem.agent_options SET group_id = $2
    WHERE group_id = $1 AND pem_user = $4
    RETURNING 1
),
insert_agent_options AS (
    INSERT INTO pem.agent_options(agent_id, description, group_id, pem_user)
    SELECT id, description, $2, $4 FROM pem.agent a
    WHERE a.group_id = $1 AND NOT a.id = ANY(
        SELECT ao.agent_id FROM pem.agent_options ao WHERE ao.pem_user = $4
    ) RETURNING 1
),
update_server_options AS (
    UPDATE pem.server_options SET server_group_id = $3
    WHERE server_group_id = $1 AND pem_user = $4
    RETURNING 1
),
insert_server_options AS (
    INSERT INTO pem.server_options(
        server_id, server_group_id, pem_user, server_colour, fgcolor,
        database_restriction, store_pwd, restore_env,
        connect_timeout, sslcompression, username
    ) SELECT
        so.server_id, $3, $4, so.server_colour, so.fgcolor,
        so.database_restriction, false, so.restore_env,
        connect_timeout, sslcompression, username
    FROM pem.server_options so
    LEFT JOIN pem.server s ON (so.server_id = s.id)
    LEFT JOIN pg_roles r ON (s.owner = r.oid)
    WHERE s.group_id = $1 AND r.rolname = so.pem_user AND
        NOT s.id = ANY(
            SELECT c.server_id FROM pem.server_options c
            WHERE c.pem_user = $4
        )
    RETURNING 1
)
SELECT sum(g.cnt) FROM (
    SELECT count(*) AS cnt FROM update_agent_options
    UNION ALL
    SELECT count(*) AS cnt FROM insert_agent_options
    UNION ALL
    SELECT count(*) AS cnt FROM update_server_options
    UNION ALL
    SELECT count(*) AS cnt FROM insert_server_options
) g$SQL$ USING _old, _aid, _sid, v_user INTO v_cnt;
    RETURN v_cnt;
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.hide_server_group(
    _id integer,
    _uid integer default pem.current_user_id()
)
RETURNS integer AS
$$
DECLARE
    v_name text;
    v_hidden bool;
    v_cnt integer;
BEGIN
    -- Move the servers, and agents to the default respective groups
    -- i.e. Move servers in group #1 (PEM Server Directory), and agents in the
    -- group #0 (PEM Agents)
    SELECT pem.change_server_group(_id, 0, 1, _uid) INTO v_cnt;

    SELECT hidden INTO v_hidden FROM pem.user_server_group
    WHERE id = _id AND uid = _uid;

    IF FOUND THEN
        IF NOT v_hidden THEN
            UPDATE pem.user_server_group SET hidden = TRUE
            WHERE id = _id AND uid = _uid;
        ELSE
            RETURN -1;
        END IF;
    ELSE
        INSERT INTO pem.user_server_group(id, name, hidden, uid)
        SELECT s.id, s.name, TRUE, _uid FROM pem.server_group s WHERE s.id = _id;
    END IF;
    RETURN 0;
END$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.delete_server_group(
    _id integer, new_implementation boolean default false,
    _uid integer default pem.current_user_id()
)
RETURNS boolean AS
$$
DECLARE
    v_name text;
    v_cnt integer;
BEGIN
    PERFORM pem.hide_server_group(_id, _uid);
    IF NOT new_implementation THEN
        RETURN false;
    END IF;

    -- 'pem.hide_server_group' will already inserted the required row (if not
    -- present already)
    UPDATE pem.user_server_group SET deleted = true
    WHERE id = _id AND uid = _uid;

    -- Check - how many servers, and agents are present under the agents for
    -- other users, if none then remove it permenantly.
    SELECT SUM(g.cnt) INTO v_cnt FROM (
        SELECT count(*) AS cnt FROM pem.server_options
        WHERE server_group_id = _id
        UNION ALL
        SELECT count(*) AS cnt FROM pem.agent_options WHERE group_id = _id
    ) g;

    IF v_cnt = 0 THEN
        UPDATE pem.server SET group_id = 1 WHERE group_id = _id;
        UPDATE pem.agent SET group_id = 0 WHERE group_id = _id;
        DELETE FROM pem.server_group WHERE id = _id;
        RETURN true;
    END IF;

    RETURN false;
END$$ LANGUAGE 'plpgsql' SECURITY DEFINER;

END TRANSACTION;

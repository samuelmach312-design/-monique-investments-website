{% if server_id is defined %}
SELECT
    count(*)
FROM
    pem.server_options
WHERE
    server_id = {{server_id}}::int4 AND
    pem_user = current_user;
{% elif server_group_id is defined %}
SELECT
    name, parent_id
FROM
    pem.server_group
WHERE
    id={{server_group_id}}::int4;
{% else %}
SELECT
    (CASE WHEN
        COALESCE(o.username, oa.username) = {{data.username}}:: AND
        COALESCE(o.server_group_id, oa.server_group_id, 1) = {{data.gid}}::text AND
        COALESCE(o.database_restriction, oa.database_restriction) = {{data.db_restriction}}::text AND
        COALESCE(o.store_pwd, oa.store_pwd) =  {{data.store_pwd}}::boolean AND
        COALESCE(o.restore_env, oa.restore_env) =  {{data.restore_env}}::boolean AND
        COALESCE(o.last_database, oa.last_database) = {{data.last_database}}::text AND
        COALESCE(o.last_schema, oa.last_schema) = {{data.last_schema}}::text AND
        COALESCE(o.rolename, oa.rolename) = {{data.role}}::text
        COALESCE(o.connection_params, oa.connection_params) = {{data.connection_params}}::text
    THEN False
    ELSE True
    END)::boolean AS is_different
FROM
    pem.server s
    LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
    LEFT OUTER JOIN pem.server_options o ON (s.id = o.server_id AND o.pem_user = current_user)
    LEFT OUTER JOIN pem.server_options oa
        ON (o.id IS NULL AND s.id = oa.server_id AND
            (owner.rolename = oa.pem_user OR (owner.rolename IS NULL AND oa.pem_user IS NULL)))
WHERE
    s.id = {{data.server_id}}::int4;
{% endif %}

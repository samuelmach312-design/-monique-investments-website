SELECT
    s.*,
    COALESCE(usg.name, sg.name) AS server_group_name
FROM (
    SELECT
        s.id, s.description AS name, s.server AS host,
        s.port, s.database, s.serviceid, s.active,
        s.hostaddr, s.alert_blackout, s.owner,
        s.team, s.server_owner, s.is_remote_monitoring,
        s.efm_cluster_name, s.efm_service_name, s.efm_installation_path,
        s.replication_solution,
        s.patroni_cluster_name, s.patroni_installation_path, s.patroni_config_path,
        ps.comment,
        ps.tags,
        ps.comment, ps.tags, ps.post_connection_sql,
        ps.profile_id,
        COALESCE(o.pem_user, oa.pem_user) AS option_pem_username,
        COALESCE(o.username, oa.username) AS username,
        COALESCE(o.server_group_id, oa.server_group_id, 1)::text AS gid,
        COALESCE(o.database_restriction, oa.database_restriction) AS db_restriction,
        COALESCE(o.store_pwd, oa.store_pwd) AS store_pwd,
        COALESCE(o.restore_env, oa.restore_env) AS restore_env,
        COALESCE(o.last_database, oa.last_database) AS last_database,
        COALESCE(o.last_schema, oa.last_schema) AS last_schema,
        COALESCE(o.rolename, oa.rolename) AS role,
        {% if schema_version is defined and schema_version >= 202508141 %}
            COALESCE(
                CASE WHEN o.server_id IS NOT NULL THEN o.connection_params ELSE oa.connection_params END,
                '{}'::jsonb
            ) AS connection_params,
        {% else %}
            CASE WHEN o.server_id IS NOT NULL THEN o.connect_timeout ELSE oa.connect_timeout END as connect_timeout,
        {% endif %}
        COALESCE(sinf.server_version_id > 20000, false) AS is_edb,
        o_auth.ssl_root_cert AS ssl_root_cert,
        o_auth.ssl_rev_list AS ssl_rev_list,
        o_auth.ssl_client_cert AS ssl_client_cert,
        o_auth.ssl_client_key AS ssl_client_key,
        o_auth.passfile AS passfile,
        o.sslcompression AS sslcompression,
        COALESCE(o_auth.use_ssh_tunnel, false) as use_ssh_tunnel,
        o_auth.tunnel_host as tunnel_host,
        COALESCE(o_auth.tunnel_port, 22) as tunnel_port,
        o_auth.tunnel_username as tunnel_username,
        COALESCE(o_auth.tunnel_authentication, false) as tunnel_authentication,
        o_auth.tunnel_identity_file as tunnel_identity_file,
        o_auth.tunnel_password as tunnel_password,
        CASE WHEN o.pem_user IS NULL THEN oa.server_colour
        ELSE o.server_colour END AS bgcolor,
        CASE WHEN o.pem_user IS NULL THEN oa.fgcolor
        ELSE o.fgcolor END AS fgcolor,
        b.agent_id AS agent_id,
        b.server AS asb_host,
        b.port AS asb_port,
        b.username AS asb_username,
        b.database AS asb_database,
        b.sslmode AS asb_sslmode,
        '' AS asb_password,
        b.exclude_databases AS asb_exclude_databases,
        b.allow_takeover AS agent_allowtakeover,
        a.agent_capability_list AS agent_capability_list,
        a.description AS agent_description,
        COALESCE(o_auth.save_password, false) as is_password_saved,
        CASE WHEN coalesce(o_auth.tunnel_password, '') = '' THEN false ELSE true END as is_tunnel_password_saved
{% if schema_version is defined and schema_version >= 202104021 %}
        , COALESCE(o_auth.use_gssapi, false) as kerberos_conn
{% endif %}
    FROM pem.avail_servers s
        LEFT JOIN pem.server ps ON (s.id = ps.id)
        LEFT OUTER JOIN pem.server_options o ON (s.id = o.server_id AND o.pem_user = CURRENT_USER)
        LEFT OUTER JOIN pem.server_options oa ON (s.id = oa.server_id AND (s.server_owner = oa.pem_user or oa.pem_user IS NULL))
        LEFT OUTER JOIN pem.server_auth o_auth ON (s.id = o_auth.server_id AND o_auth.pem_user = CURRENT_USER)
        LEFT OUTER JOIN pemdata.server_info sinf ON(s.id = sinf.server_id)
        LEFT OUTER JOIN pem.agent_server_binding b ON (s.id = b.server_id)
        LEFT OUTER JOIN pem.avail_agents a ON (b.agent_id = a.id)
{% if sid %}
    WHERE s.id = {{sid}}
{% endif %}
{% if sgid %}
    WHERE COALESCE(o.server_group_id, oa.server_group_id, 1) = {{sgid}}
{% endif %}
    ) s
    LEFT OUTER JOIN pem.server_group sg ON (sg.id::text = s.gid)
    LEFT OUTER JOIN pem.user_server_group usg ON (usg.id::text = s.gid AND usg.uid = pem.current_user_id())

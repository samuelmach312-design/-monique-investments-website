SELECT
    a.*, COALESCE(u.name, sg.name) AS server_group_name
FROM (
    SELECT
        s.id, s.description AS name, s.server AS host,
        s.port, s.database, s.serviceid, s.active,
        s.hostaddr, s.alert_blackout, s.owner,
        s.team, s.server_owner, s.is_remote_monitoring,
        s.efm_cluster_name, s.efm_installation_path,
        s.replication_solution,
        s.patroni_cluster_name, s.patroni_installation_path,s.patroni_config_path,
        s.description || ' (' || s.server || ':' || s.port::text || ')' AS description,
        srv.profile_id,
        p.name AS profile_name,
        'true' AS "isLazy",
        COALESCE(o.database_restriction, oa.database_restriction) AS db_restriction,
        COALESCE(o.username, oa.username) AS username,
        COALESCE(o.rolename, oa.rolename) AS role,
        COALESCE(
                CASE WHEN o.server_id IS NOT NULL THEN o.connection_params ELSE oa.connection_params END,
                '{}'::jsonb
            ) AS connection_params,
        'password' as password,
        COALESCE(o.server_group_id, oa.server_group_id, 1) AS server_group_id,
        CASE WHEN o.pem_user IS NULL THEN oa.server_colour
        ELSE o.server_colour END AS bgcolor,
        CASE WHEN o.pem_user IS NULL THEN oa.fgcolor
        ELSE o.fgcolor END AS fgcolor,
        curr_user_auth.ssl_root_cert AS ssl_root_cert,
        curr_user_auth.ssl_rev_list AS ssl_rev_list,
        curr_user_auth.ssl_client_cert AS ssl_client_cert,
        curr_user_auth.ssl_client_key AS ssl_client_key,
        curr_user_auth.passfile AS passfile,
        curr_user_op.sslcompression AS sslcompression,
        COALESCE(curr_user_auth.use_ssh_tunnel, false) as use_ssh_tunnel,
        curr_user_auth.tunnel_host as tunnel_host,
        COALESCE(curr_user_auth.tunnel_port, 22) as tunnel_port,
        curr_user_auth.tunnel_username as tunnel_username,
        COALESCE(curr_user_auth.tunnel_authentication, false) as tunnel_authentication,
        curr_user_auth.tunnel_identity_file as tunnel_identity_file,
        curr_user_auth.tunnel_password as tunnel_password,
        COALESCE(curr_user_auth.save_password, false) as is_password_saved,
        CASE WHEN COALESCE(curr_user_auth.tunnel_password, '') = '' THEN false ELSE true END as is_tunnel_password_saved,
        CASE WHEN COALESCE(asb.agent_id, -1) = -1 THEN false ELSE true END as is_agent_binded,
        srv.tags AS tags, srv.post_connection_sql AS post_connection_sql
{% if schema_version is defined and schema_version >= 202104021 %}
        , COALESCE(curr_user_auth.use_gssapi, false) as kerberos_conn
{% endif %}
    FROM
        (SELECT * FROM pem.avail_servers {% if sid %} WHERE id = {{ sid|qtLiteral(conn) }} {% endif %}) s
        LEFT JOIN pem.server srv ON s.id = srv.id
        LEFT JOIN pem.profile p ON srv.profile_id = p.id
        LEFT OUTER JOIN pem.server_options o ON (
            s.id = o.server_id AND (
                o.pem_user = CURRENT_USER OR o.pem_user IS NULL
            )
        )
        LEFT OUTER JOIN pem.server_options oa ON (
            s.id = oa.server_id AND s.server_owner = oa.pem_user
        )
        LEFT OUTER JOIN pem.agent_server_binding asb ON (s.id = asb.server_id)

        LEFT OUTER JOIN pem.server_options curr_user_op ON (
            s.id = curr_user_op.server_id AND (
                curr_user_op.pem_user = CURRENT_USER)
        )
        LEFT OUTER JOIN pem.server_auth curr_user_auth ON (
            s.id = curr_user_auth.server_id AND (
                curr_user_auth.pem_user = CURRENT_USER)
        )
    ) a
    LEFT JOIN pem.user_server_group u
        ON ( a.server_group_id = u.id AND u.uid = pem.current_user_id() )
    LEFT JOIN pem.server_group sg
        ON sg.id = a.server_group_id
{% if not sid and sgid is defined and sgid >= 0 %}
WHERE a.server_group_id = {{ sgid|qtLiteral(conn) }}::int4
{% endif %}
 ORDER BY a.description, a.port;

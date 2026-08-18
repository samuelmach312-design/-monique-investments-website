SELECT
    s.id,
    s.description as name,
    s.server AS host,
    s.port AS port,
    server.tags AS tags,
    server.post_connection_sql AS post_connection_sql,
    COALESCE(o.username, oa.username) AS username,
    COALESCE(o.server_group_id, oa.server_group_id, 1) AS server_group_id,
    COALESCE(o.fgcolor, oa.fgcolor) AS fgcolor,
    COALESCE(o.server_colour, oa.server_colour) AS bgcolor,
    COALESCE(curr_user_auth.use_ssh_tunnel, false) as use_ssh_tunnel,
    curr_user_auth.tunnel_host AS tunnel_host,
    COALESCE(curr_user_auth.tunnel_port, 22) as tunnel_port,
    curr_user_auth.tunnel_username as tunnel_username,
    COALESCE(curr_user_auth.tunnel_authentication, false) as tunnel_authentication,
    curr_user_auth.tunnel_identity_file AS tunnel_identity_file,
    curr_user_auth.tunnel_password as tunnel_password,
    COALESCE(o.connection_params, oa.connection_params) AS connection_params,
    s.efm_cluster_name, s.efm_installation_path,
    s.replication_solution,
    s.patroni_cluster_name, s.patroni_installation_path,s.patroni_config_path,
    s.database as maintenance_db,
    curr_user_auth.password AS password,
    curr_user_auth.passfile AS passfile,
    COALESCE(curr_user_auth.save_password, false) as is_password_saved,
    CASE WHEN COALESCE(curr_user_auth.tunnel_password, '') = '' THEN false ELSE true END as is_tunnel_password_saved,
    CASE WHEN COALESCE(asb.agent_id, -1) = -1 THEN false ELSE true END as is_agent_binded
{% if schema_version is defined and schema_version >= 202104021 %}
    , COALESCE(curr_user_auth.use_gssapi, false) as kerberos_conn
{% endif %}
FROM
    pem.avail_servers s
    LEFT OUTER JOIN pem.server_options o ON (s.id = o.server_id AND o.pem_user = CURRENT_USER)
    LEFT OUTER JOIN pem.server server ON (s.id = server.id AND o.pem_user = CURRENT_USER)
    LEFT OUTER JOIN pem.server_options oa ON (s.id = oa.server_id AND s.server_owner = oa.pem_user)
    LEFT OUTER JOIN pem.server_auth curr_user_auth ON (s.id = curr_user_auth.server_id AND curr_user_auth.pem_user = CURRENT_USER)
    LEFT OUTER JOIN pem.agent_server_binding asb ON (s.id = asb.server_id)
{% if sid is not none %}
  WHERE s.id = {{sid}}::int4
{% endif %}
{% if sgid %}
  AND COALESCE(o.server_group_id, oa.server_group_id) = {{sgid}}::int4
{% endif %}

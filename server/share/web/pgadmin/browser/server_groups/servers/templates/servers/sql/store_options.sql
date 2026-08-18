{% if insert_server_auth %}
INSERT INTO
    pem.server_auth (
        server_id, pem_user, ssl_root_cert, ssl_rev_list, ssl_client_cert,
        ssl_client_key, save_password, password, passfile, use_ssh_tunnel, tunnel_host, tunnel_port,
        tunnel_username, tunnel_authentication, tunnel_identity_file, tunnel_password
{% if schema_version is defined and schema_version >= 202104021 %}
, use_gssapi
{% endif %}
    )
VALUES
    (
        {{data.server_id|qtLiteral(conn)}}::int4, current_user,
        {{data.ssl_root_cert|qtLiteral(conn,True)}}::text, {{data.ssl_rev_list|qtLiteral(conn,True)}}::text,
        {{data.ssl_client_cert|qtLiteral(conn, True)}}::text, {{data.ssl_client_key|qtLiteral(conn, True)}}::text,
        {{data.save_password}}::boolean, {{data.password|qtLiteral(conn, True)}}::text, {{data.passfile|qtLiteral(conn, True)}}::text,
        {%if data.use_ssh_tunnel is defined and data.use_ssh_tunnel is not none %}{{data.use_ssh_tunnel|qtLiteral(con)}}{% else %}'false'{% endif %}::boolean,
        {%if data.tunnel_host is defined and data.tunnel_host is not none %}{{data.tunnel_host|qtLiteral(conn, True)}}{% else %}''{% endif %}::text,
        {%if data.tunnel_port is defined and data.tunnel_port is not none %}{{data.tunnel_port|qtLiteral(con)}}{% else %}'22'{% endif %}::int4,
        {%if data.tunnel_username is defined and data.tunnel_username is not none %}{{data.tunnel_username|qtLiteral(conn, True)}}{% else %}''{% endif %}::text,
        {%if data.tunnel_authentication is defined and data.tunnel_authentication is not none %}{{data.tunnel_authentication|qtLiteral(conn)}}{% else %}'false'{% endif %}::boolean,
        {%if data.tunnel_identity_file is defined and data.tunnel_identity_file is not none %}{{data.tunnel_identity_file|qtLiteral(conn, True)}}{% else %}''{% endif %}::text,
        {%if data.tunnel_password is defined and data.tunnel_password is not none %}{{data.tunnel_password|qtLiteral(conn, True)}}{% else %}NULL{% endif %}::text
{% if schema_version is defined and schema_version >= 202104021 %}
, {% if data.kerberos_conn is defined and data.kerberos_conn is not none %}{{data.kerberos_conn|qtLiteral(conn)}}{% else %}'false'{% endif %}::boolean
{% endif %}

    );
{% endif %}

{% if insert_server_options %}
    INSERT INTO
    pem.server_options (
        server_id, pem_user, server_group_id,
        database_restriction, last_database,
        last_schema, rolename, sslcompression,
        server_colour, fgcolor, username, connection_params
    )
VALUES
    (
        {{data.server_id|qtLiteral(conn)}}::int4, current_user, {{data.gid|qtLiteral(conn)}}::int4,
        {{data.db_res|qtLiteral(conn, True)}}::text, {{data.last_database|qtLiteral(conn, True)}}::text,
        {{data.last_schema|qtLiteral(conn, True)}}::text, {{data.role|qtLiteral(conn, True)}}::text,
        {{data.sslcompression}}::boolean, {{data.bgcolor|qtLiteral(conn, True)}}::text,
        {{data.fgcolor|qtLiteral(conn, True)}}::text,
        {{data.username|qtLiteral(conn, True)}}::text,
        {{ data.connection_params | tojson | qtLiteral(conn, True) }}::jsonb
    );
{% endif %}

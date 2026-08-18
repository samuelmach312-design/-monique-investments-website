{% if data %}
{% set flag = False %}
  {% if data.gid is defined or
        data.db_res is defined or
        data.username is defined or
        data.store_pwd is defined or
        data.restore_env is defined or
        data.last_database is defined or
        data.last_schema is defined or
        data.role is defined or
        data.sslcompression is defined or
        data.bgcolor is defined or
        data.fgcolor is defined or
        data.connection_params is defined %}

    UPDATE
        pem.server_options
    SET
    {% if data.gid is defined %}
        server_group_id = {{data.gid}}::int4
        {% set flag = True %}
    {% endif %}
    {% if data.db_res is defined %}
        {% if flag == True %}, {% endif %}{% set flag = True %}database_restriction = {{data.db_res|qtLiteral(conn, True)}}::text
    {% endif %}
    {% if data.store_pwd is defined %}
        {% if flag == True %}, {% endif %}{% set flag = True %}store_pwd = {{data.store_pwd}}::boolean
    {% endif %}
    {% if data.restore_env is defined %}
        {% if flag == True %}, {% endif %}{% set flag = True %}restore_env = {{data.restore_env}}::boolean
    {% endif %}
    {% if data.last_database is defined %}
        {% if flag == True %}, {% endif %}{% set flag = True %}last_database = {{data.last_database|qtLiteral(conn, True)}}::text
    {% endif %}
    {% if data.last_schema is defined %}
        {% if flag == True %}, {% endif %}{% set flag = True %}last_schema = {{data.last_schema|qtLiteral(conn, True)}}::text
    {% endif %}
    {% if data.role is defined %}
        {% if flag == True %}, {% endif %}{% set flag = True %}rolename = {{data.role|qtLiteral(conn, True)}}::text
    {% endif %}
    {% if data.sslcompression is defined %}
        {% if flag == True %}, {% endif %}{% set flag = True %}sslcompression = {{data.sslcompression}}::boolean
    {% endif %}
    {% if data.bgcolor is defined %}
        {% if flag == True %}, {% endif %}{% set flag = True %}server_colour = {{data.bgcolor|qtLiteral(conn, True)}}::text
    {% endif %}
    {% if data.fgcolor is defined %}
        {% if flag == True %}, {% endif %}{% set flag = True %}fgcolor = {{data.fgcolor|qtLiteral(conn, True)}}::text
    {% endif %}
    {% if data.connection_params is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}connection_params = {% if data.connection_params != '' %}{{ data.connection_params | tojson | qtLiteral(conn, True) }}::jsonb{% else %}NULL{% endif %}
    {% endif %}
    {% if data.username is defined %}
        {% if flag == True %}, {% endif %}{% set flag = True %}username = {{data.username|qtLiteral(conn, True)}}::text
    {% endif %}
    WHERE
      server_id = {{server_id}}::int4 AND
      pem_user = current_user;

  {% endif %}

  {% set flag_auth = False %}

  {% if data.ssl_root_cert is defined or
        data.ssl_rev_list is defined or
        data.ssl_client_cert is defined or
        data.ssl_client_key is defined or
        data.save_password is defined or
        data.password is defined or
        data.passfile is defined or
        data.use_ssh_tunnel is defined or
        data.tunnel_host is defined or
        data.tunnel_port is defined or
        data.tunnel_username is defined or
        data.tunnel_authentication is defined or
        data.tunnel_identity_file is defined or
        data.tunnel_password is defined or
        data.kerberos_conn is defined %}

    UPDATE
        pem.server_auth
    SET
    {% if data.ssl_root_cert is defined %}
        {% set flag_auth = True %}ssl_root_cert = {{data.ssl_root_cert|qtLiteral(conn, True)}}::text
    {% endif %}
    {% if data.ssl_rev_list is defined %}
        {% if flag_auth == True %}, {% endif %}{% set flag_auth = True %}ssl_rev_list = {{data.ssl_rev_list|qtLiteral(conn, True)}}::text
    {% endif %}
    {% if data.ssl_client_cert is defined %}
        {% if flag_auth == True %}, {% endif %}{% set flag_auth = True %}ssl_client_cert = {{data.ssl_client_cert|qtLiteral(conn, True)}}::text
    {% endif %}
    {% if data.ssl_client_key is defined %}
        {% if flag_auth == True %}, {% endif %}{% set flag_auth = True %}ssl_client_key = {{data.ssl_client_key|qtLiteral(conn, True)}}::text
    {% endif %}
    {% if data.save_password is defined %}
        {% if flag_auth == True %}, {% endif %}{% set flag_auth = True %}save_password = {{data.save_password}}::boolean
    {% endif %}
    {% if data.password is defined %}
        {% if flag_auth == True %}, {% endif %}{% set flag_auth = True %}password = {% if data.password is none %}NULL{% else %}{{data.password|qtLiteral(conn, True)}}::text{% endif %}
    {% endif %}
    {% if data.passfile is defined %}
        {% if flag_auth == True %}, {% endif %}{% set flag_auth = True %}passfile = {{data.passfile|qtLiteral(conn, True)}}::text
    {% endif %}
    {% if data.use_ssh_tunnel is defined %}
        {% if flag_auth == True %}, {% endif %}{% set flag_auth = True %}use_ssh_tunnel = {{data.use_ssh_tunnel}}::boolean
    {% endif %}
    {% if data.tunnel_host is defined %}
        {% if flag_auth == True %}, {% endif %}{% set flag_auth = True %}tunnel_host = {{data.tunnel_host|qtLiteral(conn, True)}}::text
    {% endif %}
    {% if data.tunnel_port is defined %}
        {% if flag_auth == True %}, {% endif %}{% set flag_auth = True %}tunnel_port = {{data.tunnel_port|qtLiteral(conn)}}::int4
    {% endif %}
    {% if data.tunnel_username is defined %}
        {% if flag_auth == True %}, {% endif %}{% set flag_auth = True %}tunnel_username = {{data.tunnel_username|qtLiteral(conn, True)}}::text
    {% endif %}
    {% if data.tunnel_authentication is defined %}
        {% if flag_auth == True %}, {% endif %}{% set flag_auth = True %}tunnel_authentication = {{data.tunnel_authentication}}::boolean
    {% endif %}
    {% if data.tunnel_identity_file is defined %}
        {% if flag_auth == True %}, {% endif %}{% set flag_auth = True %}tunnel_identity_file = {{data.tunnel_identity_file|qtLiteral(conn, True)}}::text
    {% endif %}
    {% if data.tunnel_password is defined %}
        {% if flag_auth == True %}, {% endif %}{% set flag_auth = True %}tunnel_password = {% if data.tunnel_password is none %}NULL{% else %}{{data.tunnel_password|qtLiteral(conn, True)}}::text{% endif %}
    {% endif %}
    {% if data.kerberos_conn is defined %}
        {% if flag_auth == True %}, {% endif %}{% set flag_auth = True %}use_gssapi = {{data.kerberos_conn}}::boolean
    {% endif %}
    WHERE
        server_id = {{server_id}}::int4 AND
        pem_user = current_user;
  {% endif %}
{% endif %}

/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2025, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////

// auth_sources is not required for PEM
define('pgadmin.user_management.current_user', [], function () {
  return {
    'id': '{{ user_id }}',
    'email': '{{ email }}',
    'is_admin': {{ is_admin }},
    'name': '{{ name }}',
    'allow_save_password': {{ allow_save_password }},
    'allow_save_tunnel_password': {{ allow_save_tunnel_password }},
    'current_auth_source': '{{ current_auth_source }}',
    'uid' : '{{ uid }}',
    'pem_super_admin': {{ pem_super_admin }},
    'is_pem_admin': {{ is_pem_admin }},
    'allow_auth_other_than_kerberos': {{ allow_auth_other_than_kerberos }},
    'permissions': {{ permissions }},
    'pem_database_server_registration': {{ pem_database_server_registration }}
    }
});

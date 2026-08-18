SELECT pem.delete_server_group(
    {{ id|qtLiteral }}::integer, true, pem.current_user_id()::integer
);

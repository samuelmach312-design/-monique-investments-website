SELECT pem.rename_server_group(
    {{id}}, {{name|qtLiteral}}, pem.current_user_id()
);

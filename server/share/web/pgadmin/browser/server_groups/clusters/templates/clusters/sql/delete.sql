SELECT pem.delete_cluster({{ id|qtLiteral(conn) }}::integer);

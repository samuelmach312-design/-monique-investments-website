WITH server_replication AS (
  SELECT replication_solution
  FROM pem.server
  WHERE id = (%(sid)s)::int4
)
SELECT
CASE
  WHEN COALESCE(NULLIF(sr.replication_solution, ''), NULL) IS NULL THEN
    (
      (SELECT count(*) FROM pemdata.wal_archive_status WHERE server_id = (%(sid)s)::int4) > 0 OR
      (SELECT count(*) FROM pemdata.streaming_replication WHERE server_id = (%(sid)s)::int4) > 0 OR
      (SELECT count(*) FROM pemdata.streaming_replication_lag_time WHERE server_id = (%(sid)s)::int4) > 0
    )

  WHEN sr.replication_solution = 'efm' THEN
    (
      (SELECT count(*) FROM pemdata.wal_archive_status WHERE server_id = (%(sid)s)::int4) > 0 OR
      (SELECT count(*) FROM pemdata.streaming_replication WHERE server_id = (%(sid)s)::int4) > 0 OR
      (SELECT count(*) FROM pemdata.streaming_replication_lag_time WHERE server_id = (%(sid)s)::int4) > 0 OR
      (SELECT count(*) FROM pemdata.efm_cluster_node_status WHERE server_id = (%(sid)s)::int4) > 0 OR
      (SELECT count(*) FROM pemdata.efm_cluster_info WHERE server_id = (%(sid)s)::int4) > 0
    )

  WHEN sr.replication_solution = 'patroni' THEN
    (
      (SELECT count(*) FROM pemdata.wal_archive_status WHERE server_id = (%(sid)s)::int4) > 0 OR
      (SELECT count(*) FROM pemdata.streaming_replication WHERE server_id = (%(sid)s)::int4) > 0 OR
      (SELECT count(*) FROM pemdata.streaming_replication_lag_time WHERE server_id = (%(sid)s)::int4) > 0 OR
      (SELECT count(*) FROM pemdata.patroni_cluster_status WHERE server_id = (%(sid)s)::int4) > 0 OR
      (SELECT count(*) FROM pemdata.patroni_node_status WHERE server_id = (%(sid)s)::int4) > 0
    )

  ELSE false
END
FROM server_replication sr;
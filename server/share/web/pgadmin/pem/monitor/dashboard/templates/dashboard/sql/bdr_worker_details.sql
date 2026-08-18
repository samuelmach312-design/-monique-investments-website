SELECT row_to_json(
        (SELECT x FROM (
		SELECT worker_pid as "Worker PID", query_start as "Query Start", state_change as "State Change", wait_event_type as "Wait Event Type",
		wait_event as "Wait Event", state as "State", worker_role_name as "Worker Role Name",
		worker_commit_timestamp as "Worker Commit Timestamp", worker_local_timestamp as "Worker Local Timestamp",
		origin_name as "Origin Name", receive_lsn as "Receive LSN", receive_commit_lsn as "Receive Commit LSN", last_xact_replay_lsn as "Last xact Replay LSN",
		last_xact_flush_lsn as "Last xact Flush LSN", last_xact_replay_timestamp as "Last xact Replay Timestamp", query as "Query"
		from pemdata.bdr_workers
		where server_id={{ server_id }} and worker_pid = {{ worker_pid|qtLiteral(conn) }} limit 1
        ) x),
        true
);

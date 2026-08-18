SELECT row_to_json(
        (SELECT x FROM (
		select worker_pid as "Worker PID", node_group_name as "Node Group Name", origin_name as "Origin Name",
		source_name as "Source Name", target_name as "Target Name", sub_name as "Subscription Name", worker_role as "Worker Role",
		worker_role_name as "Worker Role Name", error_time as "Error Time", error_age as "Error Age",
		error_message as "Error Message", error_context_message as "Error Context Message",
        remoterelid as "Remote Relation ID", subwriter_id as "Subscription Writer ID", subwriter_name as "Subscription Writer Name" from pemdata.bdr_worker_errors
		where server_id={{ server_id }} and worker_pid = {{ worker_pid|qtLiteral(conn) }} limit 1
        ) x),
        true
);

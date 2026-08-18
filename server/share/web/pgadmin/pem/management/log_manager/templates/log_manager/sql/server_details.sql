WITH log_settings AS (
SELECT server_id, name, setting FROM pemdata.settings
WHERE name IN ('log_destination', 'logging_collector', 'log_directory', 'log_filename', 'log_line_prefix')
)
SELECT  pdlc.server_id,
        CASE (position('stderr' in (SELECT setting FROM log_settings ls WHERE ls.server_id = pdlc.server_id AND name = 'log_destination')))
        WHEN 0 THEN false
        ELSE true
        END AS log_destination_stderr,

        CASE (position('csvlog' in (SELECT setting FROM log_settings ls WHERE ls.server_id = pdlc.server_id AND name = 'log_destination')))
        WHEN 0 THEN false
        ELSE true
        END AS log_destination_csvlog,

        CASE (position('syslog' in (SELECT setting FROM log_settings ls WHERE ls.server_id = pdlc.server_id AND name = 'log_destination')))
        WHEN 0 THEN false
        ELSE true
        END AS log_destination_syslog,

        CASE (position('eventlog' in (SELECT setting FROM log_settings ls WHERE ls.server_id = pdlc.server_id AND name = 'log_destination')))
        WHEN 0 THEN false
        ELSE true
        END AS log_destination_eventlog,

        (SELECT setting='on' FROM log_settings WHERE server_id = pdlc.server_id AND name = 'logging_collector') AS log_collector,
        (SELECT setting FROM log_settings WHERE server_id = pdlc.server_id AND name = 'log_directory') AS log_directory,
        (SELECT setting FROM log_settings WHERE server_id = pdlc.server_id AND name = 'log_filename') AS log_filename,
        (SELECT setting FROM log_settings WHERE server_id = pdlc.server_id AND name = 'log_line_prefix') AS log_prefix_string,
        pdlc.log_silent_mode,
        pdlc.log_syslog_facility,
        pdlc.log_syslog_ident,
        pdlc.log_rotation_size,
        pdlc.log_rotation_time,
        pdlc.log_rotation_truncate,
        pdlc.log_client_min_messages,
        pdlc.log_min_messages,
        pdlc.log_min_error_statement,
        pdlc.log_min_duration_statement,
        pdlc.log_parse_tree,
        pdlc.log_rewriter_output,
        pdlc.log_exec_plan,
        pdlc.log_indent_debug_output,
        pdlc.log_checkpoints,
        pdlc.log_connections,
        pdlc.log_disconnections,
        pdlc.log_duration,
        pdlc.log_hostname,
        pdlc.log_lock_waits,
        pdlc.log_error_verbosity,
        pdlc.log_statements,
        pdlc.log_autovacuum_min_duration,
        pdlc.log_temp_files,
        plc.log_import,
        plc.log_import_frequency
FROM
    pemdata.log_configuration pdlc
    LEFT JOIN pem.log_configuration plc
    ON pdlc.server_id = plc.server_id
WHERE pdlc.server_id IN ({{placeholders}})

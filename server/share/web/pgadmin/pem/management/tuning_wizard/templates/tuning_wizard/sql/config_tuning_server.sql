SELECT tuned_server_id, tuned_parameter, tuned_value, orig_value
FROM pem.server_tuning ((%(server_id_{{cnt}})s)::int,
    (%(util)s)::pem.tuning_server_util,
    (%(workload)s)::pem.tuning_workload_profile)
SELECT
    t.folder_id AS folder_id, f.title AS category, t.name AS chart_title,
    CASE t.time_period
    WHEN 'START_DATE_TO_END_DATE' THEN (CASE WHEN t.end_date > now()
        THEN (EXTRACT(EPOCH FROM now() - t.start_date)/86400)::integer ELSE
        (EXTRACT(EPOCH FROM t.end_date - t.start_date)/86400)::integer END)
    WHEN 'START_DATE_TO_THREHOLD' THEN
         (EXTRACT(EPOCH FROM now() - t.start_date) / 86400)::integer
    WHEN 'HISTORIC_DATE_TO_EXTRAPOLATED_DATE' THEN
         (CASE WHEN t.historical_days IS NOT NULL
          THEN t.historical_days ELSE 7 END)
    ELSE CASE WHEN t.historical_days IS NOT NULL THEN
        t.historical_days ELSE 7 END
    END AS historical_days,
    CASE t.time_period
    WHEN 'START_DATE_TO_END_DATE' THEN CASE WHEN t.end_date > now()
    THEN (EXTRACT(EPOCH FROM t.end_date - now())/86400)::integer ELSE 0 END
    WHEN 'START_DATE_TO_THREHOLD' THEN NULL
    WHEN 'HISTORIC_DATE_TO_THRESHOLD' THEN NULL
    ELSE CASE WHEN t.extrapolated_days IS NOT NULL THEN t.extrapolated_days
    ELSE 0 END
    END AS extrapolated_days,
    CASE WHEN t.time_period = 'START_DATE_TO_END_DATE' THEN 'E'
         WHEN t.time_period = 'HISTORIC_DATE_TO_EXTRAPOLATED_DATE' THEN 'E'
         WHEN t.time_period = 'START_DATE_TO_THREHOLD' THEN 'T'
         WHEN t.time_period = 'HISTORIC_DATE_TO_THRESHOLD' THEN 'T'
    ELSE
        'E'
    END AS cm_type,
    t.threshold_index AS metric_idx,
    t.threshold_value AS tval,
    t.threshold_opr   AS toperator
FROM pem.cm_template t
LEFT JOIN pem.cm_template_path f ON (t.folder_id = f.id)
WHERE t.id = (%s)::integer;

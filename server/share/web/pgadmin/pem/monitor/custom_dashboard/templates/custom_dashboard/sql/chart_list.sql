SELECT
    cc.name AS category, c.id AS cid, c.name AS name,
    array (SELECT CASE x.llevel
        WHEN 50 THEN 'Global'
        WHEN 100 THEN 'Agent'
        WHEN 200 THEN 'Server'
        WHEN 300 THEN 'Database'
        WHEN 400 THEN 'Schema'
        ELSE 'Hmm' END
FROM (SELECT unnest(level) AS llevel) x) AS level,
    CASE c.type
    WHEN 'B' THEN
        CASE
        WHEN fid IS NOT NULL THEN 'Bar Chart (System generated)'
        WHEN bc.type = 'D' THEN 'Bar Chart (Probe Data)'
        END
    WHEN 'P' THEN
        CASE
        WHEN fid IS NOT NULL THEN 'Pie Chart (System generated)'
        WHEN bc.type = 'D' THEN 'Pie Chart (Probe Data)'
        END
    WHEN 'TB' THEN
        CASE
        WHEN fid IS NOT NULL THEN 'Table Chart (System generated)'
        WHEN tc.type = 'D' THEN 'Table Chart (Data)'
        WHEN tc.type = 'H' THEN 'Table Chart (History Data)'
        WHEN tc.type = 'M' THEN 'Table Chart (Aggregated Data)'
        END
    WHEN 'TE' THEN
        CASE
        WHEN fid IS NOT NULL THEN 'Text Details'
        END
    WHEN 'L' THEN
        CASE
        WHEN fid IS NOT NULL THEN 'Line Chart (System generated)'
        WHEN lc.type = 'M' THEN 'Line Chart (Aggregated Data)'
        END
    WHEN 'CL' THEN
        CASE cr.type
        WHEN 'E' THEN 'Line Chart (Capacity Manager - Extrapolated days)'
        ELSE 'Line Chart (Capacity Manager - Threshold value)'
        END
    WHEN 'CT' THEN
        CASE cr.type
        WHEN 'E' THEN 'Table Chart (Capacity Manager - Extrapolated days)'
        ELSE 'Table Chart (Capacity Manager - Threshold value)'
        END
    END AS type,
    c.type AS ttype,
    c.descp AS description,
    CASE WHEN c.owner = 0 THEN true ELSE FALSE END AS system_level,
    CASE WHEN o.rolname IS NULL AND c.owner = 0 THEN '<Postgres Enterprise Manager>' WHEN o.rolname IS NULL THEN '<Unknown>' ELSE o.rolname END AS owner,
    CASE
    WHEN fid IS NOT NULL THEN c.labels::text[]
    WHEN c.type = 'B' THEN
        CASE
        WHEN bc.type = 'D' THEN
            array(SELECT pm.display_name || ' [' || pt.display_name || ']'
                FROM pem.data_chart dc
                    LEFT JOIN pem.probe pt ON (dc.tbl = pt.internal_name)
                    LEFT JOIN pem.probe_column pm ON (pm.probe_id = pt.id)
                WHERE pm.internal_name = ANY(dc.metrices) AND dc.cid = c.id)::text[]
        ELSE NULL::text[] END
    WHEN c.type = 'TB' THEN
        CASE tc.type
        WHEN 'D' THEN
            array(SELECT pm.display_name || ' [' || pt.display_name || ']'
                FROM pem.data_chart dc
                    LEFT JOIN pem.probe pt ON (dc.tbl = pt.internal_name)
                    LEFT JOIN pem.probe_column pm ON (pm.probe_id = pt.id)
                WHERE pm.internal_name = ANY(dc.metrices) AND dc.cid = c.id)::text[]
        WHEN 'H' THEN
            array(SELECT pm.display_name || ' [' || pt.display_name || ']'
                FROM pem.history_chart hc
                    LEFT JOIN pem.probe pt ON (hc.tbl = pt.internal_name)
                    LEFT JOIN pem.probe_column pm ON (pm.probe_id = pt.id)
                WHERE pm.internal_name = ANY(hc.metrices) AND hc.cid = c.id)::text[]
        WHEN 'M' THEN
            array(SELECT pm.display_name || ' [' || pt.display_name || ']'
                FROM pem.chart_metric cm
                    LEFT JOIN pem.probe pt ON (cm.tbl = pt.internal_name)
                    LEFT JOIN pem.probe_column pm ON (pm.probe_id = pt.id)
                WHERE pm.internal_name = ANY(cm.metrices) AND cm.cid = c.id)::text[]
        ELSE NULL::text[] END
    WHEN c.type = 'L' THEN
        CASE WHEN c.fid IS NOT NULL THEN c.labels::text[]
        ELSE array(SELECT
                CASE
                WHEN m.params IS NULL OR array_length(m.params, 1) = 0 THEN
                    pc.display_name
                WHEN p.applies_to_id <> 800 THEN
                    pc.display_name || ' (' || COALESCE(a.description, s.description) || '/' || array_to_string(ARRAY(SELECT pg_catalog.quote_ident((m.params)[s].value) FROM generate_series (2, array_upper(m.params, 1), 1) AS s), '/') || ')'
                ELSE
                    pc.display_name || ' (' || COALESCE(a.description, s.description) || '/' || array_to_string(ARRAY(SELECT pg_catalog.quote_ident((m.params)[s].value) FROM generate_series (2, array_upper(m.params, 1) - 2, 1) AS s), '/') || '(' || COALESCE(((m.params)[array_upper(m.params, 1)].value), '') ||  '))'
                END ||  ' [' || p.display_name || ']'
            FROM pem.chart_metric m
            LEFT JOIN pem.probe p ON (m.tbl = p.internal_name)
            LEFT JOIN (
                SELECT
                    probe_id, id, internal_name,
                    CASE WHEN is_graphable AND NOT pit_by_default THEN display_name || '+' ELSE display_name END AS display_name,
                    CASE WHEN NOT is_graphable THEN 'x' ELSE 'f' END AS pit
                FROM pem.probe_column
                UNION ALL
                SELECT
                    probe_id, id, internal_name || '_pit' AS probe_col_name, display_name, 't' AS pit
                FROM pem.probe_column
                WHERE is_graphable AND NOT pit_by_default AND calculate_pit) pc
                ON (pc.probe_id = p.id AND ARRAY[pc.internal_name] <@ m.metrices::text[])
                LEFT JOIN pem.agent a ON (m.params IS NOT NULL AND array_length(m.params, 1) <> 0 AND a.id = ((m.params)[1]).value::int4 AND p.applies_to_id = 100)
                LEFT JOIN pem.server s ON (m.params IS NOT NULL AND array_length(m.params, 1) <> 0 AND s.id = ((m.params)[1]).value::int4 AND p.applies_to_id > 100)
            WHERE m.cid = c.id)::text[]
        END
    WHEN c.type = 'P' THEN
        CASE
        WHEN pc.type = 'D' THEN
            array(SELECT pm.display_name || ' [' || pt.display_name || ']'
                FROM pem.data_chart dc
                    LEFT JOIN pem.probe pt ON (dc.tbl = pt.internal_name)
                    LEFT JOIN pem.probe_column pm ON (pm.probe_id = pt.id)
                WHERE pm.internal_name = ANY(dc.metrices) AND dc.cid = c.id)::text[]
        ELSE NULL::text[] END
    WHEN c.type = 'CL' OR c.type = 'CT' THEN
            ARRAY(SELECT
                CASE
                WHEN p.applies_to_id <> 800 THEN
                    pc.display_name || ' (' || COALESCE(a.description, s.description) || '/' || array_to_string(ARRAY(SELECT pg_catalog.quote_ident((m.params)[s].value) FROM generate_series (2, array_upper(m.params, 1), 1) AS s), '/') || ')'
                ELSE
                    pc.display_name || ' (' || COALESCE(a.description, s.description) || '/' || array_to_string(ARRAY(SELECT pg_catalog.quote_ident((m.params)[s].value) FROM generate_series (2, array_upper(m.params, 1) - 2, 1) AS s), '/') || '(' || COALESCE(((m.params)[array_upper(m.params, 1)].value), '') ||  '))'
                END
            FROM pem.chart_metric m
            LEFT JOIN pem.probe p ON (m.tbl = p.internal_name)
            LEFT JOIN (SELECT
                probe_id, id, internal_name,
                CASE WHEN is_graphable AND NOT pit_by_default THEN display_name || '+' ELSE display_name END AS display_name,
                CASE WHEN NOT is_graphable THEN 'x' ELSE 'f' END AS pit
            FROM pem.probe_column
            UNION ALL
            SELECT
                probe_id, id, internal_name || '_pit' AS probe_col_name, display_name, 't' AS pit
            FROM pem.probe_column
            WHERE is_graphable AND NOT pit_by_default AND calculate_pit) pc
                ON (pc.probe_id = p.id AND ARRAY[pc.internal_name] <@ m.metrices::text[])
            LEFT JOIN pem.agent a ON (a.id = ((m.params)[1]).value::int4 AND p.applies_to_id = 100)
            LEFT JOIN pem.server s ON (s.id = ((m.params)[1]).value::int4 AND p.applies_to_id > 100)
                WHERE m.cid = c.id)::text[]
    ELSE NULL::text[] END AS metrices
FROM pem.chart c
    LEFT JOIN pem.chart_category cc ON (c.cid = cc.id)
    LEFT JOIN pg_catalog.pg_roles o ON (c.owner = o.oid)
    LEFT JOIN pem.bar_chart bc ON (c.id = bc.cid)
    LEFT JOIN pem.line_chart lc ON (c.id = lc.cid)
    LEFT JOIN pem.pie_chart pc ON (c.id = pc.cid)
    LEFT JOIN pem.tbl_chart tc ON (c.id = tc.cid)
    LEFT JOIN pem.capacity_report_chart cr ON (c.id = cr.cid)
WHERE
    NOT c.deleted
    AND (((SELECT max(l.level) FROM (SELECT unnest(c.level) AS level) AS l) < (%(level)s)::int4) OR ((%(level)s)::int4 = ANY (c.level)))
    AND (o.oid IS NULL -- This is a system level chart
        OR o.rolname = current_user -- This user is the owner of the chart
        OR pem.can_access(c.shared)) -- The chart is shared with this user
    AND CASE c.type
    WHEN 'B' THEN
            CASE
                WHEN (fid IS NOT NULL OR bc.type = 'D') THEN true
                ELSE false
            END
    WHEN 'P' THEN
        CASE
        WHEN (fid IS NOT NULL OR bc.type = 'D') THEN true
        ELSE false
        END
    WHEN 'TB' THEN
        CASE
        WHEN (fid IS NOT NULL OR tc.type IN ('D', 'H', 'M')) THEN true
        ELSE false
        END
    WHEN 'TE' THEN
        CASE
        WHEN fid IS NOT NULL THEN true
        ELSE false
        END
    WHEN 'L' THEN
        CASE
        WHEN (fid IS NOT NULL OR lc.type = 'M') THEN true
        ELSE false
        END
    WHEN 'CL' THEN
        (fid IS NULL)
    WHEN 'CT' THEN
        (fid IS NULL)
    END
    AND c.type != 'TE'
ORDER BY cc.name, (SELECT max(l.level) FROM (SELECT unnest(c.level) AS level) AS l), type, c.name
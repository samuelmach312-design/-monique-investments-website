SELECT
    s.jstid AS id,
    s.jstname AS step,
    s.jstdesc AS description,
    s.jstenabled AS enabled,
    CASE s.jstkind
        WHEN 's' THEN 'SQL'
        WHEN 'b' THEN 'Batch'
        WHEN 'i' THEN 'Internal'
    END AS kind,
    jsl.jslstatus AS status,
    NULL AS result,
    NULL AS output,
    EXTRACT(EPOCH FROM jsl.jslstart) AS last_run,
    NULL AS duration
FROM pem.job jb
LEFT JOIN pem.jobstep s ON s.jstjobid = jb.jobid
LEFT JOIN pem.jobsteplog jsl ON jsl.jsljstid = s.jstid
    AND jsl.jslid = (
        SELECT MAX(j.jslid)
        FROM pem.jobsteplog as j
        WHERE j.jsljstid = s.jstid
    )
WHERE jb.jobid = %(jid)s::int
ORDER BY last_run DESC

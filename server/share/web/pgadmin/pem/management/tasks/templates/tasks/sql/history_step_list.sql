SELECT
    num AS jsljlgid,
    l.jslid AS job_step_log_id,
    s.jstname AS step,
    s.jstdesc AS description,
    CASE s.jstkind
        WHEN 's' THEN 'SQL'
        WHEN 'b' THEN 'Batch'
        WHEN 'i' THEN 'Internal'
    END AS kind,
    COALESCE(l.jslstatus, 'n') AS status,
    l.jslresult AS result,
    CASE
        WHEN char_length(l.jsloutput) > {{max_chars}} THEN
            CONCAT(LEFT(l.jsloutput, {{max_chars}}), '...')
        ELSE
            LEFT(l.jsloutput, {{max_chars}})
    END AS output,
    EXTRACT(EPOCH FROM l.jslstart) AS start_time,
    EXTRACT(EPOCH FROM l.jslduration) AS duration
FROM pem.jobstep s
RIGHT JOIN (
    SELECT jlgid, jlgjobid, ROW_NUMBER() OVER (ORDER BY jlgid) AS num
    FROM pem.joblog
    WHERE jlgjobid = %(jid)s::int
) jl ON s.jstjobid = jl.jlgjobid
RIGHT JOIN pem.jobsteplog l ON s.jstid = l.jsljstid AND jl.jlgid = l.jsljlgid
WHERE s.jstjobid = %(jid)s::int
    AND l.jsljlgid = %(job_log_id)s::int;
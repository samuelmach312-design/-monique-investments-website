SELECT
    DISTINCT(j.jobid) AS taskid,
    j.jobname AS taskname,
    j.jobdesc AS desc,
    j.jobenabled AS enabled,
    j.jobcreated AS created,
    j.jobnextrun AS nextrun,
    j.joblastrun AS lastrun,
    j.issystemjob AS systemjob,
    COALESCE((
        SELECT
            l.jlgstatus
        FROM
            pem.joblog l
        WHERE
            l.jlgjobid = j.jobid
        ORDER BY l.jlgstart DESC LIMIT 1
        )::character varying(1), 'n') AS status,
    a.description AS agent,
    a.id AS agent_id,
    se.description AS server,
    se.id AS server_id
FROM
    pem.job j
    LEFT OUTER JOIN pem.jobstep s ON j.jobid = s.jstjobid
    LEFT OUTER JOIN pem.avail_agents a ON j.agent_id = a.id
    LEFT OUTER JOIN pem.avail_servers se ON s.server_id = se.id
        WHERE a.id = (SELECT asb.agent_id FROM pem.agent_server_binding asb WHERE asb.server_id = (%s)::int4 LIMIT 1)
            AND se.id = (%s)::int4
            AND j.jobdesc = 'scheduled traces'
         ORDER BY j.jobcreated DESC;
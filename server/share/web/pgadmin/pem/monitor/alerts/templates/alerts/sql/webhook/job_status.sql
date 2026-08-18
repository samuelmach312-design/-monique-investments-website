Select COALESCE((SELECT
            l.jlgstatus
        FROM
            pem.joblog l
        WHERE
            l.jlgjobid = {{job_id}}::integer
        )::character varying(1), 'n')
        AS status

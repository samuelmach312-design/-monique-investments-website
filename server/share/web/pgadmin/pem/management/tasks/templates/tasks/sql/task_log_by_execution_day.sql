SELECT
  jl.jlgjobid as taskid,
  j.jobdesc AS desc,
  to_char(jl.jlgstart::timestamp, 'YYYY-MM-DD') as ex_time
FROM
  pem.joblog jl
  LEFT JOIN pem.job j ON j.jobid = jl.jlgjobid
WHERE  jl.jlgjobid =  %(jid)s::int

UNION

SELECT
  jb.jobid as taskid,
  jb.jobdesc AS desc,
  to_char(jb.jobnextrun::timestamp, 'YYYY-MM-DD') as ex_time
FROM pem.job jb
WHERE jb.jobid = %(jid)s::int AND
      jb.jobnextrun IS NOT NULL

GROUP BY ex_time, jb.jobid
ORDER BY ex_time DESC;
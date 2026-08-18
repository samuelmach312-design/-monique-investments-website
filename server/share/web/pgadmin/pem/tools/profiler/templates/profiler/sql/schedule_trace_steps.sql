SELECT
  s.jstname AS name,
  s.jstdesc AS desc,
  s.jstenabled AS enabled,
  CASE s.jstkind
        WHEN 's' THEN 'SQL'
        WHEN 'b' THEN 'Batch'
        WHEN 'i' THEN 'Internal'
  END AS kind,
  COALESCE(l.jslstatus, 'n') AS status,
  l.jslresult AS result,
  l.jsloutput AS output,
  l.jslstart::timestamp(0) AS start,
  l.jslduration AS duration
FROM
  pem.jobstep s
  LEFT JOIN pem.jobsteplog l ON s.jstid = l.jsljstid
WHERE  jstjobid = (%s);
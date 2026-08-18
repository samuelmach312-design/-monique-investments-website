SELECT jsloutput AS output
FROM pem.jobsteplog
WHERE jslid = %(jslid)s::int

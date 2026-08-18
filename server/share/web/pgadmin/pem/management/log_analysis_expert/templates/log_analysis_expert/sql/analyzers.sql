SELECT  id, analyzer_name
FROM  pem.logexp_charts
WHERE analyzer_name IS NOT NULL
ORDER BY id ASC
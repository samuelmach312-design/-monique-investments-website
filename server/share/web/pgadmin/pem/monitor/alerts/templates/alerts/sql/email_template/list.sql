SELECT
	et.id as id,
    et.display_name as template,
    COALESCE(cet.mail_subject, et.mail_subject) AS mail_subject,
    COALESCE(cet.mail_message, et.mail_message) AS mail_message,
    CASE WHEN et.display_name LIKE 'Alert%' THEN 'Alert'::text ELSE 'Job'::text END AS category,
    CASE WHEN cet.display_name IS NOT NULL THEN false ELSE true END AS is_default,
    CASE WHEN cet.display_name IS NOT NULL THEN 'y'::text ELSE 'n'::text END AS is_custom_str
FROM
    pem.email_template AS et
LEFT JOIN pem.custom_email_template AS cet 
    ON (et.display_name = cet.display_name)
ORDER BY et.id;
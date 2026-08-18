DELETE FROM
    pem.custom_email_template
WHERE display_name = %(template)s::text

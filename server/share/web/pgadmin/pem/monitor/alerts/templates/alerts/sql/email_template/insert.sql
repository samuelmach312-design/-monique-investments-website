{% set flag = False %}
{% if mail_subject is defined and mail_subject == '' %}
    {% set mail_subject = None %}
{% endif %}

INSERT INTO pem.custom_email_template
    (display_name, mail_subject, mail_message)
VALUES (
    %(template)s,
    %(mail_subject)s,
    %(mail_message)s
)
ON CONFLICT (display_name)
DO UPDATE SET 
    pem_user = current_user
    {% if mail_subject is defined and mail_subject %},
        mail_subject = %(mail_subject)s
    {% endif %}
    {% if mail_message is defined and mail_message %},
        mail_message = %(mail_message)s
    {% endif %}
;
{% if update_job %}
    UPDATE pem.job
    SET
        {% if 'jscenabled' in data %}
            jobenabled={% if data.jscenabled %}true{% else %}false{% endif %}
        {% endif %}

    WHERE jobid={{ job_id|qtLiteral }}::integer;
{% endif %}

{% if update_jobstep %}
    UPDATE pem.jobstep
    SET
        {% if 'jscenabled' in data %}
            jstenabled={% if data.jscenabled %}true{% else %}false{% endif %}
        {% endif %}

    WHERE jstjobid={{ job_id|qtLiteral }}::integer;
{% endif %}

{% if update_schedule %}
    UPDATE pem.schedule
    SET
        {% if 'jscenabled' in data %}
            jscenabled={% if data.jscenabled %}true{% else %}false{% endif %}{% if 'jscstart' in data or 'jscend' in data or 'jscmonths' in data or 'jscminutes' in data or 'jscmonthdays' in data or 'jschours' in data or 'jscweekdays' in data %},{% endif %}
        {% endif %}{% if 'jscstart' in data %}
            jscstart={{ data.jscstart|qtLiteral }}::timestamptz{% if 'jscend' in data or 'jscmonths' in data or 'jscminutes' in data or 'jscmonthdays' in data or 'jschours' in data or 'jscweekdays' in data %},{% endif %}
        {% endif %}{% if 'jscend' in data %}
            jscend={% if data.jscend %}{{ data.jscend|qtLiteral }}::timestamptz{% else %}NULL::timestamptz{% endif %}{% if 'jscmonths' in data or 'jscminutes' in data or 'jscmonthdays' in data or 'jschours' in data or 'jscweekdays' in data %},{% endif %}
        {% endif %}{% if 'jscmonths' in data %}
            jscmonths=ARRAY[{{ data.jscmonths|join(', ')}}]::boolean[]{% if 'jscminutes' in data or 'jscmonthdays' in data or 'jschours' in data or 'jscweekdays' in data %},{% endif %}
        {% endif %}{% if 'jscminutes' in data %}
            jscminutes=ARRAY[{{ data.jscminutes|join(', ')}}]::boolean[]{% if 'jscmonthdays' in data or 'jschours' in data or 'jscweekdays' in data %},{% endif %}
        {% endif %}{% if 'jscmonthdays' in data %}
            jscmonthdays=ARRAY[{{ data.jscmonthdays|join(', ')}}]::boolean[]{% if 'jschours' in data or 'jscweekdays' in data %},{% endif %}
        {% endif %}{% if 'jschours' in data %}
            jschours=ARRAY[{{ data.jschours|join(', ')}}]::boolean[]{% if 'jscweekdays' in data %},{% endif %}
        {% endif %}{% if 'jscweekdays' in data %}
            jscweekdays=ARRAY[{{ data.jscweekdays|join(', ')}}]::boolean[]{% endif %}

    WHERE jscjobid={{ job_id|qtLiteral }}::integer;
{% endif %}

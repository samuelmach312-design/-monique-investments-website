{% import 'macros/pem_jobschedule.macros' as SCHEDULE %}
DO $$
DECLARE
    scid integer;
BEGIN
{{ SCHEDULE.INSERT(jid, data) }}
END
$$;

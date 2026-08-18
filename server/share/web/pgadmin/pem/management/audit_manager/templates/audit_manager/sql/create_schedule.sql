INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays,
                         jscmonthdays, jscmonths)
VALUES ((%s)::int, 'Audit Log Collection',
        'This job schedule runs periodically to collect audit logs data',
        (%s)::boolean[], (%s)::boolean[],
        '{t,t,t,t,t,t,t}',
        '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}',
        '{t,t,t,t,t,t,t,t,t,t,t,t}')

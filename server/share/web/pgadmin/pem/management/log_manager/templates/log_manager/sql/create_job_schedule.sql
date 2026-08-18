INSERT INTO pem.schedule(
    jscjobid,
    jscname,
    jscdesc,
    jscminutes,
    jschours,
    jscweekdays,
    jscmonthdays,
    jscmonths
  )
VALUES (
    (%s)::int,
    'PEM Log Manager Log Import',
    'This job schedule runs periodically to collect logs data',
    (%s)::boolean[],
    (%s)::boolean[],
    '{t,t,t,t,t,t,t}',
    '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}',
    '{t,t,t,t,t,t,t,t,t,t,t,t}'
  );
 SELECT
   jl.jlgid AS job_log_id,
   jl.jlgjobid as taskid,
   j.jobdesc AS desc,
   j.jobname AS name,
   jl.jlgstatus AS status,
   EXTRACT(EPOCH FROM jl.jlgstart) AS start_time,
   EXTRACT(EPOCH FROM jl.jlgduration) AS duration
 FROM
   pem.joblog jl
   LEFT JOIN pem.job j ON j.jobid = jl.jlgjobid
   LEFT OUTER JOIN pem.jobstep s ON j.jobid = s.jstjobid
   LEFT OUTER JOIN pem.avail_agents a ON j.agent_id = a.id
   LEFT OUTER JOIN pem.avail_servers se ON s.server_id = se.id
   LEFT OUTER JOIN pg_catalog.pg_roles r ON (j.userid = r.oid)
WHERE 
  {% set and_flag = False %}
  {% if data.db_name and data.db_name != -1 %}
    {% set and_flag = True %}
    s.database_name = %(db_name)s
    AND se.id = (%(server_id)s)::int4
  {% else %}
    {% if data.agent_id and data.agent_id != -1 %}
      a.id = (%(agent_id)s)::int4
      {% set and_flag = True %}
    {% endif %}
    {% if data.server_id and data.server_id != -1 %}
      {% if and_flag %} AND{% endif %} se.id = (%(server_id)s)::int4
    {% endif %}
  {% endif %}
  {% if not (data.show_sys_tasks and data.show_sys_tasks == 1) %}
    AND issystemjob = false
  {% endif %}
  {% if data.search_query %}
      AND (
          to_tsvector('english', j.jobname) @@ to_tsquery('english', %(search_query)s)
          OR jl.jlgid::text ILIKE %(search_query_like)s
          OR jl.jlgjobid::text ILIKE %(search_query_like)s
      )
  {% endif %}
GROUP BY
  jl.jlgid, jl.jlgjobid, j.jobdesc, j.jobname, jl.jlgstatus, jl.jlgstart, jl.jlgduration
ORDER BY jl.jlgstart DESC, jlgid DESC 
LIMIT %(page_size)s OFFSET %(offset)s;
select json_agg(c.configs)
from (
	select json_build_object('label', label, 'value', value, 'category', category) as configs
	from pem.agent_config
	where agent_id = {{agent_id}}
	order by id) as c;

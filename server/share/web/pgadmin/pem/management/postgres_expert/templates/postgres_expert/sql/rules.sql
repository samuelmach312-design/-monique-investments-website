 {# Expert/Rule selection statement #}
SELECT
	array_agg(ruletext.id) rule_id_list,
	array_agg(ruletext.name) rule_list,
	expert.name expert_name,
	expert.id expert_id
FROM
    pem.pe_rules_text ruletext
LEFT JOIN (
    pem.pe_experts expert JOIN pem.pe_rules rules
    ON (rules.expert = expert.id)
    )
ON (rules.id = ruletext.rule_id)
GROUP BY
    expert_name,
    expert_id
ORDER by
    expert_name;
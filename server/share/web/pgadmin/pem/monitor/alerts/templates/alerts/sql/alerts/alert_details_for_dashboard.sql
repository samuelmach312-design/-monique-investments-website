SELECT
    pas.info_cols as detail_info_cols,
    pas.info_vals as detail_info_rows,
    pt.param_names AS param_names,
    pal.params AS param_values
FROM
    pem.alert pal
    LEFT JOIN pem.alert_template pt ON (pt.id = pal.template_id)
    LEFT JOIN pem.alert_status pas ON (pal.id = pas.alert_id)
WHERE pal.id = (%(alert_id)s)::int4

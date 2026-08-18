select 'Agents' as object_type, count(*) from pem.agent where active
UNION
select 'Servers' as object_type, count(*) from pem.server where active
UNION
select 'Tables' as object_type, count(*) from pemdata.oc_table 
UNION
select 'Indexes' as object_type, count(*) from pemdata.oc_index 
UNION
select 'Databases' as object_type, count(*) from pemdata.oc_database
UNION
select 'Schemas' as object_type, count(*) from pemdata.oc_schema
def transform_snmp_version_value(alert, request):
    if request.blueprint in ['v1_api', 'v2_api']:
        if request.method == 'GET':
            # Due to  SNMP v3 support converting `snmp_trap_version`
            # V2 API output to boolean value
            if 'snmp_trap_version' in alert and \
                    alert['snmp_trap_version'] == '2':
                alert['snmp_trap_version'] = False
            else:
                alert['snmp_trap_version'] = True
        elif request.method in ['POST', 'PUT']:
            if 'snmp_trap_version' in alert and \
                    alert['snmp_trap_version'] is True:
                alert['snmp_trap_version'] = '1'
            else:
                alert['snmp_trap_version'] = '2'
    return alert

///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import getApiInstance from 'sources/api_instance';
import url_for from 'sources/url_for';
import { convertToMinutesAndSeconds, toHHMMSS } from '../../../../common/utils';


export const treatSavePayload = (data) => {
  const processProbeConfig = (probe) => {
    if (probe.execution_frequency) {
      const { minutes, seconds, total_interval } = convertToMinutesAndSeconds(
        probe.execution_frequency
      );
      probe.interval_min = minutes;
      probe.interval_sec = seconds;
      probe.interval = total_interval;
      probe.execution_frequency= total_interval;
    }

    if (probe.enabled_default) {
      probe.enabled_by_default = probe.enabled_default === 'default';
    }

    if (probe.lifetime !== null && probe.lifetime !== undefined) {
      probe.lifetime = Number(probe.lifetime);
    }
  };

  const processEntries = (entries) => {
    entries?.forEach((entry) => {
      entry.target_probe_configs?.forEach?.(processProbeConfig);
      entry.target_probe_configs?.changed?.forEach?.(processProbeConfig);

    });
  };

  processEntries(data.added);
  processEntries(data.changed);

  return data;
};


export const transformProbesData = (data) => {
  const probeConfigs = [];
  let res = {target_probe_configs: probeConfigs};

  data?.forEach((row) => {
    probeConfigs.push({
      probe_id: row.probe_id,
      probe_name: row.probe_name,

      default_interval_min: Math.floor(row.default_interval / 60),
      default_interval_sec: row.default_interval % 60,
      default_lifetime: row.default_lifetime,

      default_enabled: row.default_enabled,
      use_default_enabled: row.default_enabled === row.enabled,
      enabled: row.enabled,
      enabled_status:
        row.default_enabled === row.enabled
          ? 'default'
          : row.enabled
            ? 'enabled'
            : 'disabled',

      use_default_interval: row.interval === row.default_interval,
      interval_min: Math.floor(row.interval / 60),
      interval_sec: row.interval % 60,
      target_type_id_returned: row.target_type_id_returned,
      execution_frequency: toHHMMSS(row.interval),
      default_execution_frequency: toHHMMSS(
        row.default_interval
      ),
      target_type: row.target_type,
      use_default_lifetime: row.default_lifetime === row.lifetime,
      lifetime: row.lifetime,
      force_enabled: row.force_enabled,
      // has_different_target_type:
      //   row.target_type_id_returned !== monitoring_level,
    });
  });

  // Sort data based on target_type_id_returned (descending order)
  probeConfigs.sort(
    (a, b) => b.target_type_id_returned - a.target_type_id_returned
  );

  return res;
};

export const transformAlertsData = (data) => {
  const configs = [];

  data?.forEach((row) => {
    configs.push({

      alert_id: row.id,
      alert_name: row.alert_name,

      template_id: row.alert_template || row.template_id,
      alert_template: row.alert_template || row.template_id,

      package_name: row.package_name,
      object_name: row.object_name,
      
      enabled: row.enabled,
      auto_created: row.auto_created,
      operator: row.operator,
      
      params: row.params,
      thresholds: row.thresholds,
      
      check_frequency: row.frequency_min || row.default_frequency || row.check_frequency || 1, 
      frequency_min: row.frequency_min || row.default_frequency || row.check_frequency || 1,
      history_retention: row.history_retention || row.default_history_retention || 30,
      frequency_default: row.frequency_default,
      history_retention_default: row.history_retention_default,
      send_email: row.send_email,
      send_trap: row.send_trap,
      snmp_trap_version: row.snmp_trap_version,

      all_alert_enable: row.all_alert_enable ?? false,
      email_group_id: row.email_group_id ?? '1',
      low_alert_enable: row.low_alert_enable ?? false,
      low_email_group_id: row.low_email_group_id ?? '1',
      med_alert_enable: row.med_alert_enable ?? false,
      med_email_group_id: row.med_email_group_id ?? '1',
      high_alert_enable: row.high_alert_enable ?? false,
      high_email_group_id: row.high_email_group_id ?? '1',
      cleared_alert_enable: row.cleared_alert_enable ?? true,

      low_threshold_value: row.thresholds[0],
      medium_threshold_value: row.thresholds[1],
      high_threshold_value: row.thresholds[2],
      object_type: row.object_type,
      flapping_detected: row.flapping_detected,
      last_flapping_detection_processed: row.last_flapping_detection_processed,

      low_send_trap: row.low_send_trap,
      med_send_trap: row.med_send_trap,
      high_send_trap: row.high_send_trap,

      execute_script: row.execute_script,
      execute_script_on_clear: row.execute_script_on_clear,
      execute_script_on_pem_server: row.execute_script_on_pem_server,
      script_code: row.script_code,
      submit_to_nagios: row.submit_to_nagios,
      
      description: row.description,
      threshold_unit: row.threshold_unit,
      
      send_notification: (row.send_notification == null
         || row.send_notification === 'None') ? true : row.send_notification,
      override_default_config: row.override_default_config,
      
      low_webhook_ids: row.low_webhook_ids || [],
      med_webhook_ids: row.med_webhook_ids || [],
      high_webhook_ids: row.high_webhook_ids || [],
      cleared_webhook_ids: row.cleared_webhook_ids || [],
    });
  });
  

  return { target_alert_configs: configs };
};


export const transformCreateAlertData = (data) =>
  data.map((row) => {
    return {
      id: row.template_id, // TODO: No id
      alert_name: row.name,
      description: row.description,
      alert_template: row.template_id, // Alert template is now id
      frequency_default: true,  
      frequency_min: row.default_check_frequency,
      default_frequency: row.default_check_frequency,
      enabled: true,
      auto_created: row.is_auto_create,
      history_retention_default: true,
      history_retention: row.default_history_retention,
      default_history_retention: row.default_history_retention,
      operator: row.operator,
      object_type: row.object_type,
      low_threshold_value: row.low_threshold_value,
      medium_threshold_value: row.medium_threshold_value,
      high_threshold_value: row.high_threshold_value,
      params: row.params,
      all_alert_enable: row.all_alert_enable ?? false,
      email_group_id: row.email_group_id ?? '1',
      low_alert_enable: row.low_alert_enable ?? false,
      low_email_group_id: row.low_email_group_id ?? '1',
      med_alert_enable: row.med_alert_enable ?? false,
      med_email_group_id: row.med_email_group_id ?? '1',
      high_alert_enable: row.high_alert_enable ?? false,
      high_email_group_id: row.high_email_group_id ?? '1',
      cleared_alert_enable: row.cleared_alert_enable ?? true,
      send_trap: row.send_trap ?? false,
      snmp_trap_version: row.snmp_trap_version ?? '2',
      low_send_trap: row.low_send_trap,
      med_send_trap: row.med_send_trap,
      high_send_trap: row.high_send_trap,
      submit_to_nagios: row.submit_to_nagios,
      execute_script: row.execute_script ?? false,
      execute_script_on_clear: row.execute_script_on_clear,
      execute_script_on_pem_server: row.execute_script_on_pem_server ?? '0',
      script_code: row.script_code,
      marked_for_deletion: row.marked_for_deletion,
      threshold_unit: row.threshold_unit,
      send_notification: row.send_notification ?? true,
      override_default_config: row.override_default_config || false,
      low_webhook_ids: row.low_webhook_ids ?? [],
      med_webhook_ids: row.med_webhook_ids ?? [],
      high_webhook_ids: row.high_webhook_ids ?? [],
      cleared_webhook_ids: row.cleared_webhook_ids ?? [],

    };});

export const transformProfileData = (data) => {
  return data.map(row => ({
    ...row,
    ...transformProbesData(JSON.parse((row.target_probe_configs))),
    ...transformAlertsData(JSON.parse((row.target_alert_configs)))
  }));
};

export const callUrl = async (url, draft_id) => {
  try {
    const res = await getApiInstance().post(url_for(url,{'draft_id': draft_id}));
    return res.data;
  } catch (error) {
    console.error(`API call to ${url} failed:`, error);
    throw error;
  }
};

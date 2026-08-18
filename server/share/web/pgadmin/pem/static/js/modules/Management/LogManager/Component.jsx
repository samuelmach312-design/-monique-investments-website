///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////
import React, { useState } from 'react';

import Box from '@mui/material/Box';
import WarningIcon from '@mui/icons-material/Warning';
import PropTypes from 'prop-types';

import url_for from 'sources/url_for';
import gettext from 'sources/gettext';
import Wizard from 'sources/helpers/wizard/Wizard';
import WizardStep from 'sources/helpers/wizard/WizardStep';
import Loader from 'sources/components/Loader';
import SchemaView from 'sources/SchemaView';
import { InputTree } from 'sources/components/FormComponents';
import getApiInstance from 'sources/api_instance';
import pgAdmin from 'sources/pgadmin';

import { InfoDiv } from 'pem/utils/styles';
import { LOG_MANAGER, FORM_INFO_MSG } from 'pem/utils/constants';
import TreeNode from 'pem/components/tree_node';
import { AlertBox } from 'pem/common/StyledComponents';
import { createTree } from 'pem/utils/helpers';

import * as schema from './schema';
import { StyledBox } from '../styles';

export default function LogManagerComponent({ closeDialog }) {

  const steps = LOG_MANAGER.STEPS_LABEL.map(step => gettext(step));
  const [loaderText, setLoaderText] = useState('');
  const [serverData, setServerData] = useState([]);
  const [serverLogData, setServerLogData] = useState([]);
  const [selectedServers, setSelectedServers] = useState([]);
  const [configLoaded, setConfigLoaded] = useState(false);
  const [serverVersions, setServerVersions] = useState([]);

  // Function to extract server versions from selected servers
  const extractServerVersions = (selectedServerIds, serverData) => {
    const versions = [];
  
    selectedServerIds.forEach(serverId => {
    // Find the server in the tree structure
      serverData.forEach(group => {
        if (group.children) {
          const server = group.children.find(s => parseInt(s.id) === serverId);
          if (server && server.server_version_id) {
            versions.push(server.server_version_id);
          }
        }
      });
    });
  
    return versions;
  };

  // Update server versions when selected servers change
  React.useEffect(() => {
    if (serverData.length > 0 && selectedServers.length > 0) {
      const versions = extractServerVersions(selectedServers, serverData);
      setServerVersions(versions);
    }
  }, [selectedServers, serverData]);

  const [formData, setFormData] = useState({
    configuration: {}, location: {}, schedule: {}, servers: {}, what: {},
    when: {}
  });
  const [logConfigSchema, setLogConfigSchema] = useState(null);
  const [logWhereSchema, setLogWhereSchema] = useState(null);
  const [logWhenSchema, setLogWhenSchema] = useState(null);
  const [logWhatSchema, setLogWhatSchema] = useState(null);
  const [logScheduleSchema, setLogScheduleSchema] = useState(null);

  const api = getApiInstance();

  const validateServer = () => {
    const servers = {
      restart_servers: [],
      servers: []
    };
    selectedServers.forEach((serverId) => {
      let server_restart = false;
      const serverObj = serverLogData.find(
        s => parseInt(s.server_id) === serverId);
      if (serverObj) {
        if (formData.location.log_collector !== serverObj.log_collector) {
          server_restart = true;
        }
        else if (formData.location.log_destination_eventlog !== serverObj.log_destination_eventlog) {
          server_restart = true;
        }
      }
      if (!(serverObj && formData.location.log_destination_stderr === serverObj.log_destination_stderr &&
        formData.location.log_destination_csvlog === serverObj.log_destination_csvlog &&
        formData.location.log_destination_syslog === serverObj.log_destination_syslog &&
        formData.location.log_destination_eventlog === serverObj.log_destination_eventlog &&
        formData.location.log_collector === serverObj.log_collector &&
        formData.location.log_silent_mode === serverObj.log_silent_mode &&
        formData.location.log_directory === serverObj.log_directory &&
        serverObj.log_filename === (formData.location.log_filename === 'DEFAULT' ? serverObj.log_filename : formData.location.log_filename) &&
        formData.location.log_syslog_facility === serverObj.log_syslog_facility &&
        formData.location.log_syslog_ident === serverObj.log_syslog_ident &&
        formData.configuration.log_import === serverObj.log_import &&
        formData.configuration.log_rotation_size === serverObj.log_rotation_size &&
        formData.configuration.log_rotation_time === serverObj.log_rotation_time &&
        formData.configuration.log_import_frequency === serverObj.log_import_frequency &&
        formData.configuration.log_rotation_truncate === serverObj.log_rotation_truncate &&
        formData.when.log_client_min_messages === serverObj.log_client_min_messages &&
        formData.when.log_min_messages === serverObj.log_min_messages &&
        formData.when.log_min_error_statement === serverObj.log_min_error_statement &&
        formData.when.log_min_duration_statement === serverObj.log_min_duration_statement &&
        formData.when.log_temp_files === serverObj.log_temp_files &&
        formData.when.log_autovacuum_min_duration === serverObj.log_autovacuum_min_duration &&
        formData.what.log_parse_tree === serverObj.log_parse_tree &&
        formData.what.log_rewriter_output === serverObj.log_rewriter_output &&
        formData.what.log_exec_plan === serverObj.log_exec_plan &&
        formData.what.log_indent_debug_output === serverObj.log_indent_debug_output &&
        formData.what.log_checkpoints === serverObj.log_checkpoints &&
        formData.what.log_connections === serverObj.log_connections &&
        formData.what.log_disconnections === serverObj.log_disconnections &&
        formData.what.log_duration === serverObj.log_duration &&
        formData.what.log_hostname === serverObj.log_hostname &&
        formData.what.log_lock_waits === serverObj.log_lock_waits &&
        formData.what.log_error_verbosity === serverObj.log_error_verbosity &&
        formData.what.log_prefix_string === serverObj.log_prefix_string &&
        formData.what.log_statements === serverObj.log_statements)) {
        servers.servers.push(serverId);
        if (server_restart) servers.restart_servers.push(serverId);
      }
    });
    return servers;
  };

  const onSave = () => {
    if (selectedServers.length < 1 ||
      logConfigSchema.validate(formData.configuration, () => { }) ||
      logWhereSchema.validate(formData.location, () => { }) ||
      logWhenSchema.validate(formData.when, () => { }) ||
      logWhatSchema.validate(formData.what, () => { }) ||
      logScheduleSchema.validate(formData.schedule, () => { })
    ) {
      pgAdmin.Browser.notifier.alert(
        gettext(LOG_MANAGER.TITLE),
        gettext(FORM_INFO_MSG));
    } else {
      const data = { ...formData };
      if (data.what.log_prefix_string === '') {
        data.what.log_prefix_string = '%t';
      }
      if(data.configuration.log_import === false) {
        data.configuration.log_import_frequency = '1 Hour';
      }
      if(!data.log_parse_tree){
        data.log_parse_tree = false;
      }
      delete data.servers;
      data.servers = validateServer();
      api.post(url_for('log_manager.server_log_config'), data)
        .then(() => {
          pgAdmin.Browser.notifier.success(gettext(LOG_MANAGER.FORM_SUCCESS_MSG));
          closeDialog();
        })
        .catch((err) => {
          pgAdmin.Browser.notifier.error(err.response.data.errormsg);
        });

    }
  };

  const onDialogHelp = () => {
    window.open(url_for('help.static', { 'filename': 'log_manager.html' }));
  };

  const formatRes = (data) => {
    return {
      configuration: {
        log_import: data?.log_import?data?.log_import:false,
        log_import_frequency: data?.log_import_frequency?data?.log_import_frequency:'1 Hour',
        log_rotation_size: data?.log_rotation_size,
        log_rotation_time: data?.log_rotation_time,
        log_rotation_truncate: data?.log_rotation_truncate,
      },
      location: {
        log_destination_stderr: data?.log_destination_stderr,
        log_destination_syslog: data?.log_destination_syslog,
        log_destination_eventlog: data?.log_destination_eventlog,
        log_collector: data?.log_collector,
        log_silent_mode: data?.log_silent_mode,
        update_log_dir: data?.update_log_dir || !(data?.log_directory !== 'pg_log' || data?.log_directory !== 'log'),
        log_directory: data?.log_directory,
        log_filename: data?.log_filename,
        log_syslog_facility: data?.log_syslog_facility,
        log_syslog_ident: data?.log_syslog_ident,
        log_destination_csvlog: data?.log_destination_csvlog
      },
      when: {
        log_autovacuum_min_duration: data?.log_autovacuum_min_duration,
        log_client_min_messages: data?.log_client_min_messages,
        log_min_duration_statement: data?.log_min_duration_statement,
        log_min_error_statement: data?.log_min_error_statement,
        log_min_messages: data?.log_min_messages,
        log_temp_files: data?.log_temp_files
      },
      what: {
        log_parse_tree: data?.log_parse_tree,
        log_rewriter_output: data?.log_rewriter_output,
        log_exec_plan: data?.log_exec_plan,
        log_indent_debug_output: data?.log_indent_debug_output,
        log_checkpoints: data?.log_checkpoints,
        log_connections: data?.log_connections,
        log_disconnections: data?.log_disconnections,
        log_duration: data?.log_duration,
        log_hostname: data?.log_hostname,
        log_lock_waits: data?.log_lock_waits,
        log_error_verbosity: data?.log_error_verbosity,
        log_prefix_string: data?.log_prefix_string,
        log_statements: data?.log_statements,
      },
      schedule: {
        configure_now: true,
        time: null
      }
    };
  };

  const onBeforeNext = (activeStep) => {
    return new Promise((resolve, reject) => {
      switch (activeStep) {
      case LOG_MANAGER.STEPS.WELCOME:
        setLoaderText(gettext('Loading Servers ...'));
        api.get(url_for('log_manager.server_list'))
          .then(res => {
            setLoaderText('');
            const tree = createTree(res.data.data, 'id');
            if (tree.length === 1 && tree[0].children.length === 1) {
              if(tree[0].children[0]?.err_msg){
                tree[0].checkbox = false;
              } else {
                tree[0].children[0].isSelected = true;
                tree[0].isSelected = true;
              }
            }
            setServerData(tree);
            resolve();
          })
          .catch(() => {
            setLoaderText('');
            reject(new Error(gettext('Error while fetching Servers.')));
          });
        break;
      case LOG_MANAGER.STEPS.SERVER_SELECTION:
        if (!configLoaded) {
          setLoaderText(gettext('Loading Server Configs...'));
          setConfigLoaded(false);
          api.get(
            url_for('log_manager.server_get_details'),
            {
              params: {
                server_ids: JSON.stringify(selectedServers),
              }
            },
          ).then(res => {
            const servers = selectedServers.map((serverId) => {
              let serverObj = null;
              serverData.forEach((server) => {
                const sObj = server.children.find(
                  s => parseInt(s.id) === serverId);
                if (sObj) serverObj = sObj;
              });
              return serverObj;
            });
            if (res?.data?.data.length) {
              setServerLogData(res?.data?.data);
              const data = formatRes(res?.data?.data[0]);
              // Check if any version in the serverVersions is 18 or higher
              const hasVersion18orHigher = (!serverVersions.every(version =>
                (version >= 11000 && version < 11800) ||
                (version >= 21000 && version < 21800)
              ));
              // If version 18+ is present, set log_connections to empty string, otherwise keep server value
              if (hasVersion18orHigher) {
                if (data.what.log_connections === 'on' || data.what.log_connections === 'off') {
                  data.what.log_connections = '';
                }
              }
              setFormData({ ...data, servers });
              setLogConfigSchema(new schema.logManagerConfigSchema());
            } else {
              setFormData({
                ...formData, servers: servers
              });
              setLogConfigSchema(new schema.logManagerConfigSchema());
            }
            setConfigLoaded(true);
            setLoaderText('');
            resolve();
          }).catch(() => {
            setLoaderText('');
            reject(new Error(gettext('Error while fetching servers config.')));
            resolve();
          });
        } else {
          resolve();
        }
        break;
      case LOG_MANAGER.STEPS.LOG_CONFIGURATION:
        if (!logWhereSchema)
          setLogWhereSchema(new schema.logManagerWhereSchema({},
            formData?.configuration?.log_import, formData.servers));
        resolve();
        break;
      case LOG_MANAGER.STEPS.WHERE_LOG:
        if (!logWhenSchema)
          setLogWhenSchema(new schema.logManagerWhenSchema({}));
        resolve();
        break;
      case LOG_MANAGER.STEPS.WHEN_LOG:
        if (!logWhatSchema)
          setLogWhatSchema(new schema.logManagerWhatSchema({},
            formData?.configuration?.log_import
          ));
        resolve();
        break;
      case LOG_MANAGER.STEPS.WHAT_LOG:
        if (!logScheduleSchema)
          setLogScheduleSchema(new schema.logManagerScheduleSchema(formData.schedule));
        resolve();
        break;
      default:
        resolve();
      }
    });
  };

  const onBeforeBack = (activeStep) => {
    return new Promise((resolve) => {
      switch (activeStep) {
      case LOG_MANAGER.STEPS.WHERE_LOG:
        setLogWhereSchema(null);
        resolve();
        break;
      case LOG_MANAGER.STEPS.WHEN_LOG:
        resolve();
        break;
      default:
        resolve();
      }
    });
  };
  const disableNextCheck = (stepId) => {
    switch (stepId) {
    case LOG_MANAGER.STEPS.SERVER_SELECTION:
      return selectedServers.length < 1;
    case LOG_MANAGER.STEPS.LOG_CONFIGURATION:
      return logConfigSchema?.validate(formData.configuration, () => { });
    case LOG_MANAGER.STEPS.WHERE_LOG:
      return logWhereSchema?.validate(formData.location, () => { });
    case LOG_MANAGER.STEPS.WHEN_LOG:
      return logWhenSchema?.validate(formData.when, () => { });
    case LOG_MANAGER.STEPS.WHAT_LOG:
      return logWhatSchema?.validate(formData.what, () => { });
    case LOG_MANAGER.STEPS.SCHEDULE_LOG:
      return logScheduleSchema?.validate(formData.schedule, () => { });
    default:
      return false;
    }
  };

  const onChange = (data) => {
    const _selectedServers = [];
    data.filter(obj => obj.isLeaf).map(server => {
      _selectedServers.push(parseInt(server.id));
    });
    setSelectedServers(_selectedServers);
    if(logConfigSchema)
      setLogConfigSchema(null);
    setConfigLoaded(false);
  };

  const getInitData = () => new Promise((resolve) => {
    resolve({
      log_import: false,
      log_import_frequency: '1 Hour',
      log_rotation_size: 10,
      log_rotation_time: 1,
      log_rotation_truncate: false,
      ...formData.configuration,
    });
  });
  const getInitDataWhere = () => new Promise((resolve) => {
    resolve({
      log_destination_stderr: true,
      log_destination_syslog: false,
      log_destination_eventlog: false,
      log_collector: true,
      log_silent_mode: false,
      update_log_dir: false,
      log_directory: 'pg_log',
      log_filename: 'DEFAULT',
      log_syslog_facility: 'LOCAL0',
      log_syslog_ident: 'postgres',
      ...formData.location,
      log_destination_csvlog: formData?.configuration?.log_import
    });
  });
  const getInitDataWhen = () => new Promise((resolve) => {
    resolve({
      log_client_min_messages: 'notice',
      log_min_messages: 'warning',
      log_min_error_statement: 'error',
      log_min_duration_statement: -1,
      log_temp_files: -1,
      log_autovacuum_min_duration: -1,
      ...formData.when,
    });
  });
  const getInitDataWhat = () => new Promise((resolve) => {
    resolve({
      log_parse_tree: false,
      log_rewriter_output: false,
      log_exec_plan: false,
      log_indent_debug_output: true,
      log_checkpoints: false,
      log_connections: '',
      log_disconnections: false,
      log_duration: false,
      log_hostname: false,
      log_lock_waits: false,
      log_error_verbosity: 'default',
      log_prefix_string: '%t',
      log_statements: 'none',
      serverVersions: serverVersions,
      ...formData.what,
    });
  });

  const getInitDataSchedule = () => new Promise((resolve) => {
    resolve({
      configure_now: true,
      time: '',
      ...formData.schedule,
    });
  });
  return (
    <StyledBox>
      <Loader message={loaderText} />
      <Wizard
        title={gettext(LOG_MANAGER.TITLE)}
        stepList={steps}
        disableNextStep={disableNextCheck}
        onSave={onSave}
        onHelp={onDialogHelp}
        beforeNext={onBeforeNext}
        beforeBack={onBeforeBack}
      >
        <WizardStep stepId={0} className="Wizard-welcomeScreen">
          <div>
            <InfoDiv>
              <h2>{gettext('Welcome to the Log Manager')}</h2>
            </InfoDiv>
            {gettext('The Log Manager allows the bulk configuration of logging and log collection on database servers.')}
          </div>
        </WizardStep>
        <WizardStep stepId={1} className='Wizard-noOverflow'>
          <Box className='Wizard-treeContainer'>
            <InputTree data={serverData}
              hasCheckbox={true}
              onChange={onChange}
              NodeComponent={TreeNode}
            />
            {selectedServers?.length === 0 && <AlertBox severity="error"
              icon={<WarningIcon />}
              className="dialog">{gettext('Please select atleast one server')}</AlertBox>}
          </Box>
        </WizardStep>
        <WizardStep stepId={2} className='Wizard-noOverflow'>
          {logConfigSchema ? <SchemaView
            formType={'dialog'}
            getInitData={getInitData}
            viewHelperProps={{ mode: 'create' }}
            schema={logConfigSchema}
            showFooter={false}
            isTabView={false}
            formClassName='Wizard-Background'
            onDataChange={(isChanged, changedData) => {
              setFormData({
                ...formData, configuration: {
                  ...formData.configuration, ...changedData
                }
              });
            }}
          /> : <></>}
        </WizardStep>
        <WizardStep stepId={3} className='Wizard-noOverflow'>
          {logWhereSchema ? <SchemaView
            formType={'dialog'}
            getInitData={getInitDataWhere}
            viewHelperProps={{ mode: 'create' }}
            schema={logWhereSchema}
            showFooter={false}
            isTabView={false}
            formClassName='Wizard-Background'
            onDataChange={(isChanged, changedData) => {
              setFormData({
                ...formData, location: {
                  ...formData.location, ...changedData
                }
              });
            }}
          /> : <></>}
        </WizardStep>
        <WizardStep stepId={4} className='Wizard-noOverflow'>
          {logWhenSchema ? <SchemaView
            formType={'dialog'}
            getInitData={getInitDataWhen}
            viewHelperProps={{ mode: 'create' }}
            schema={logWhenSchema}
            showFooter={false}
            isTabView={false}
            formClassName='Wizard-Background'
            onDataChange={(isChanged, changedData) => {
              setFormData({
                ...formData, when: {
                  ...formData.when, ...changedData
                }
              });
            }}
          /> : <></>}
        </WizardStep>
        <WizardStep stepId={5} className='Wizard-noOverflow'>
          {logWhatSchema ? <SchemaView
            formType={'dialog'}
            getInitData={getInitDataWhat}
            viewHelperProps={{ mode: 'create' }}
            schema={logWhatSchema}
            showFooter={false}
            isTabView={false}
            formClassName='Wizard-Background'
            onDataChange={(isChanged, changedData) => {
              setFormData({
                ...formData, what: {
                  ...formData.what, ...changedData
                }
              });
            }}
          /> : <></>}
        </WizardStep>
        <WizardStep stepId={6} className='Wizard-noOverflow'>
          {logScheduleSchema ? <SchemaView
            formType={'dialog'}
            getInitData={getInitDataSchedule}
            viewHelperProps={{ mode: 'create' }}
            schema={logScheduleSchema}
            showFooter={false}
            isTabView={false}
            formClassName='Wizard-Background'
            onDataChange={(isChanged, changedData) => {
              setFormData({
                ...formData, schedule: {
                  ...formData.schedule, ...changedData
                }
              });
            }}
          /> : <></>}
        </WizardStep>
      </Wizard>
    </StyledBox>
  );
}

LogManagerComponent.propTypes = {
  closeDialog: PropTypes.func.isRequired
};

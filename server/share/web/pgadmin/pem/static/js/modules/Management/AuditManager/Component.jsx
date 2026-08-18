///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////
import React, { useMemo, useState } from 'react';

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

import { InfoDiv, StyledInfoIcon } from 'pem/utils/styles';
import { AUDIT_MANAGER, FORM_INFO_MSG } from 'pem/utils/constants';
import TreeNode from 'pem/components/tree_node';
import { AlertBox } from 'pem/common/StyledComponents';
import { createTree } from 'pem/utils/helpers';

import {
  AuditManagerConfigSchema,
  AuditManagerLogSchema,
  AuditManagerScheduleSchema
} from './schema';
import { StyledBox } from '../styles';

export default function AuditManagerComponent({ closeDialog }) {

  const steps = AUDIT_MANAGER.STEPS_LABEL.map(step => gettext(step));
  const [loaderText, setLoaderText] = useState('');
  const [serverData, setServerData] = useState([]);
  const [selectedServers, setSelectedServers] = useState([]);
  const [configLoaded, setConfigLoaded] = useState(false);

  const [formData, setFormData] = useState({
    params_config: {
      edb_audit: false,
      edb_audit_destination: 'file',
      log_collection: false,
      log_collection_frequency: '1 Hour',
      log_format: 'xml',
      edb_audit_filename: 'audit-%Y-%m-%d_%H%M%S',
      change_log_directory: false,
      edb_audit_directory: 'edb_audit',
    },
    log_config: {
      edb_audit_connect: 'none',
      edb_audit_disconnect: 'none',
      edb_audit_statements: 'none',
      edb_audit_tag: '',
      edb_audit_rotation_day: 'none',
      edb_audit_rotation_size: 0,
      edb_audit_rotation_sec: 0,
      enable_log_rotation: false
    },
    schedule: {
      configure_now: true,
      configure_date_time: null
    },
    servers: []
  });
  const [logSchemaObj, setLogSchemaObj] = useState(null);
  const [configSchemaObj, setConfigSchemaObj] = useState(null);
  const api = getApiInstance();

  const scheduleSchemaObj = useMemo(() => new AuditManagerScheduleSchema(),
    [formData.servers, configLoaded]);

  const onSave = () => {
    if (selectedServers.length < 1 ||
      configSchemaObj.validate(formData.params_config, () => { }) ||
      (!formData.params_config.edb_audit && logSchemaObj?.validate(
        formData.log_config, () => { })) ||
      scheduleSchemaObj.validate(formData.schedule, () => { })
    ) {
      pgAdmin.Browser.notifier.alert(
        gettext(AUDIT_MANAGER.TITLE),
        gettext(FORM_INFO_MSG));
    } else {

      const data = {
        ...formData,
        params_config: {
          ...formData.params_config,
          log_format: formData.params_config.edb_audit ? formData.params_config.log_format : 'none'
        }
      };
      data.servers = data.servers.map((s) => {
        // if audit parameters are changed, set flag update_config to 1
        const server = selectedServers.find(ss=> ss.server_id === s.server_id);
        if (!(server && data.params_config.log_format == server.params_config.log_format &&
          data.params_config.edb_audit_filename == server.params_config.edb_audit_filename &&
          data.params_config.edb_audit_directory == server.params_config.edb_audit_directory &&
          data.log_config.edb_audit_connect == server.log_config.edb_audit_connect &&
          data.log_config.edb_audit_disconnect == server.log_config.edb_audit_disconnect &&
          data.log_config.edb_audit_rotation_size == server.log_config.edb_audit_rotation_size &&
          data.log_config.edb_audit_rotation_sec == server.log_config.edb_audit_rotation_sec &&
          data.log_config.edb_audit_rotation_day == server.log_config.edb_audit_rotation_day &&
          data.log_config.edb_audit_statements == server.log_config.edb_audit_statements &&
          data.log_config.edb_audit_tag == server.log_config.edb_audit_tag)) {
          s.update_config = 1;
        }
        return s;
      });
      delete data.params_config.servers;
      api.post(url_for('audit_manager.schedule'), data)
        .then(() => {
          pgAdmin.Browser.notifier.success(gettext(AUDIT_MANAGER.FORM_SUCCESS_MSG));
        })
        .catch((err) => {
          pgAdmin.Browser.notifier.error(err.response.data.errormsg);
        });
      closeDialog();
    }

  };

  const onDialogHelp = () => {
    window.open(url_for('help.static', { 'filename': 'audit_manager.html' }));
  };

  const onBeforeNext = (activeStep) => {
    return new Promise((resolve, reject) => {
      switch (activeStep) {
      case AUDIT_MANAGER.STEPS.WELCOME: // Welcome Panel
        setLoaderText(gettext('Loading Servers ...'));
        api.get(url_for('audit_manager.server_list'))
          .then(res => {
            setLoaderText('');
            const tree = createTree(res.data.data, 'server_id');
            if (tree.length === 1 && tree[0].children?.length === 1) {
              if (tree[0].children[0]?.err_msg) {
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
      case AUDIT_MANAGER.STEPS.SELECT_SERVERS: // Select Server Step
        if (!configLoaded) {
          setConfigSchemaObj(null);
          setLoaderText('Loading Server Configs...');
          setConfigLoaded(false);
          api.post(
            url_for('audit_manager.server_get_config'),
            {
              server_ids: selectedServers
            },
          ).then(res => {
            if (res.data.length) {
              setFormData({
                ...formData, params_config: res.data[0].params_config,
                log_config: {
                  ...res.data[0].log_config,
                  edb_audit_statements: !['none', ''].includes(
                    res.data[0].log_config.edb_audit_statements
                  ) ? res.data[0].log_config.edb_audit_statements.split(
                      ', ') : []
                },
                servers:
                    selectedServers.map((serverId) => {
                      let serverObj = null;
                      serverData.forEach((server) => {
                        const sObj = server.children.find(
                          s => s.server_id === serverId);
                        if (sObj) serverObj = sObj;
                      });
                      return serverObj;
                    })
              });
              setSelectedServers(res.data);

              setConfigSchemaObj(new AuditManagerConfigSchema({
                ...res.data[0].params_config,
                servers: formData.servers
              }));
            } else {
              setFormData({
                ...formData,
                servers:
                    selectedServers.map((serverId) => {
                      let serverObj = null;
                      serverData.forEach((server) => {
                        const sObj = server.children.find(
                          s => s.server_id === serverId);
                        if (sObj) serverObj = sObj;
                      });
                      return serverObj;
                    })
              });
              setConfigSchemaObj(new AuditManagerConfigSchema({
                ...formData.params_config,
                servers: formData.servers
              }));
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
      case AUDIT_MANAGER.STEPS.CONFIGURATION: // Configuration Step

        if (!formData?.params_config?.edb_audit) {
          resolve(true);
        }
        if (!logSchemaObj) {
          let log_config = formData.log_config;
          const enable_log_rotation = formData.params_config.edb_audit_destination === 'syslog' ? false : log_config.edb_audit_rotation_day !== 'none';
          const obj = new AuditManagerLogSchema(
            {
              ...log_config,
              enable_log_rotation: enable_log_rotation,
              edb_audit_rotation_day: enable_log_rotation ? log_config.edb_audit_rotation_day : 'none',
              edb_audit_rotation_size: enable_log_rotation ? log_config.edb_audit_rotation_size : 0,
              edb_audit_rotation_sec: enable_log_rotation ? log_config.edb_audit_rotation_sec : 0,
            },
            formData.servers, formData.params_config.edb_audit_destination
          );
          setLogSchemaObj(obj);
        }
        resolve();
        break;
      case AUDIT_MANAGER.STEPS.SCHEDULE_RUN: // Schedule or Run Step
        if (!formData?.params_config?.edb_audit)
          resolve(true);
        resolve();
        break;
      default: // Log Parameters step
        resolve();
      }
    });
  };

  const onBeforeBack = (activeStep) => {
    return new Promise((resolve) => {
      switch (activeStep) {
      case AUDIT_MANAGER.STEPS.SCHEDULE_RUN: // Schedule or Run Step
        if (!formData?.params_config?.edb_audit)
          resolve(true);
        resolve();
        break;
      default:
        resolve();
      }
    });
  };
  const disableNextCheck = (stepId) => {
    switch (stepId) {
    case AUDIT_MANAGER.STEPS.SELECT_SERVERS: // Select Server Step
      return selectedServers.length < 1;
    case AUDIT_MANAGER.STEPS.CONFIGURATION: // Configuration step
      return configSchemaObj.validate(formData.params_config, () => { });
    case AUDIT_MANAGER.STEPS.LOG_PARAMETERS: // Log Parameters Step
      return logSchemaObj.validate(formData.log_config, () => { });
    default:
      return false;
    }
  };

  const onChange = (data) => {
    const _selectedServers = [];
    data.filter(obj => obj.isLeaf && !obj.data.err_msg).map(server => {
      _selectedServers.push(parseInt(server.id));
    });
    setSelectedServers(_selectedServers);
    setConfigLoaded(false);
  };
  return (
    <StyledBox>
      <Loader message={loaderText} />
      <Wizard
        title={gettext(AUDIT_MANAGER.TITLE)}
        stepList={steps}
        disableNextStep={disableNextCheck}
        onSave={onSave}
        onHelp={onDialogHelp}
        beforeNext={onBeforeNext}
        beforeBack={onBeforeBack}
      >
        <WizardStep stepId={0} className='Wizard-welcomScreen'>
          <div>
            <InfoDiv>
              <h2>{gettext('Welcome to the Audit Manager')}</h2>
            </InfoDiv>
            {gettext('The Audit manager will configure and enable or disable audit logging and collection on EDB Postgres Advanced Server instances.')}
          </div>
        </WizardStep>
        <WizardStep stepId={1} className='Wizard-noOverflow'>
          <Box className='Wizard-treeContainer'>
            {serverData[0]?.err_msg ? (<div><InfoDiv>
              <StyledInfoIcon />{gettext(serverData[0]?.err_msg)}
            </InfoDiv></div>) : <>
              <InputTree data={serverData}
                hasCheckbox={true}
                onChange={onChange}
                NodeComponent={TreeNode}

              />
              {selectedServers?.length === 0 && <AlertBox severity="error"
                icon={<WarningIcon />}
                className="dialog">{gettext('Please select atleast one server')}</AlertBox>}
            </>}

          </Box>
        </WizardStep>
        <WizardStep stepId={2} className='Wizard-noOverflow'>
          {formData?.servers?.length && configSchemaObj ? <SchemaView
            formType={'dialog'}
            getInitData={() => {/*This is intentional (SonarQube)*/ }}
            viewHelperProps={{ mode: 'create' }}
            schema={configSchemaObj}
            showFooter={false}
            isTabView={false}
            formClassName='Wizard-Background'
            onDataChange={(isChanged, changedData) => {
              setFormData({
                ...formData, params_config: {
                  ...changedData
                }
              });
            }}
          /> : <></>}
        </WizardStep>
        <WizardStep stepId={3} className='Wizard-noOverflow'>
          {logSchemaObj ? <SchemaView
            formType={'dialog'}
            getInitData={() => {/*This is intentional (SonarQube)*/ }}
            viewHelperProps={{ mode: 'create' }}
            schema={logSchemaObj}
            showFooter={false}
            isTabView={false}
            formClassName='Wizard-Background'
            onDataChange={(isChanged, changedData) => {
              setFormData({
                ...formData,
                log_config: { ...changedData }
              });
            }}
          /> : <></>}
        </WizardStep>
        <WizardStep stepId={4} className='Wizard-noOverflow'>
          {configLoaded ? <SchemaView
            formType={'dialog'}
            getInitData={() => {/*This is intentional (SonarQube)*/ }}
            viewHelperProps={{ mode: 'create' }}
            schema={scheduleSchemaObj}
            showFooter={false}
            isTabView={false}
            formClassName='Wizard-Background'
            onDataChange={(isChanged, changedData) => {
              setFormData({
                ...formData, schedule: {
                  ...changedData
                }
              });
            }}
          /> : <></>}
        </WizardStep>
      </Wizard>
    </StyledBox>
  );
}

AuditManagerComponent.propTypes = {
  closeDialog: PropTypes.func.isRequired
};

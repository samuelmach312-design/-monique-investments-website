////////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
////////////////////////////////////////////////////////////////////////////////

import React from 'react';

import PropTypes from 'prop-types';
import AutorenewRoundedIcon from '@mui/icons-material/AutorenewRounded';

import getApiInstance from 'sources/api_instance';
import url_for from 'sources/url_for';
import gettext from 'sources/gettext';
import pgAdmin from 'sources/pgadmin';
import SchemaView from 'sources/SchemaView';

import SwitchOverSchema from './SwitchOverSchema.ui';
import { JobStatusPoller } from './Components';

export const SwitchOverView = ({
  closeDialog,
  leaderName,
  replicaNames,
  agentId,
  patroniInstallationPath,
  patroniConfigPath,
}) => {
  const switchOverSchema = React.useRef(null);
  if (!switchOverSchema.current) {
    switchOverSchema.current = new SwitchOverSchema(leaderName, replicaNames);
  }
  const api = getApiInstance();
  const dialogTitle = gettext('Switchover Patroni Cluster?');
  const dialogBody =
    gettext('Are you sure you wish to switchover Patroni cluster?') +
    '<br><br>' +
    gettext(
      'This operation will promote a replica and reconfigure the primary database as a new replica in the cluster.'
    );
  const plainTitle = gettext('Switchover Patroni Cluster');

  const handleSave = (isNew, changedData) => {
    return new Promise((resolve, reject) => {
      pgAdmin.Browser.notifier.confirm(
        dialogTitle,
        dialogBody,
        async () => {
          closeDialog(); 
          try {
            const data = {
              agent_id: agentId,
              patroni_installation_path: patroniInstallationPath,
              patroni_config_path: patroniConfigPath,
              patroni_cluster_leader: leaderName,
              patroni_cluster_candidate: changedData.candidate_name,
            };

            const patroniResult = await api.post(
              url_for('misc_utilities.switchover_patroni_cluster'),
              data
            );

            window.job_id_for_status = patroniResult.data.data.jobid;

            pgAdmin.Browser.notifier.showModal(
              gettext(`Job Result for the job '${plainTitle}'`),
              () => <JobStatusPoller />,
              {
                isFullScreen: false,
                isResizable: true,
                showFullScreen: true,
                isFullWidth: true,
              }
            );

            resolve();
          } catch (error) {
            console.error(`Error queuing ${plainTitle}:`, error);
            pgAdmin.Browser.notifier.error(
              gettext(`An error occurred queuing ${plainTitle}: `) +
                error.message
            );
            reject(error);
          }
        },
        () => reject(new Error('User cancelled switchover'))
      );
    });
  };

  return (
    <SchemaView
      formType="dialog"
      getInitData={() => {
        /*This is intentional (SonarQube)*/
      }}
      viewHelperProps={{ mode: 'create' }}
      onSave={handleSave}
      schema={switchOverSchema.current}
      showFooter={true}
      customSaveBtnName={gettext('Switchover')}
      checkDirtyOnEnableSave={true}
      showSaveButton={true}
      customSaveBtnIcon={<AutorenewRoundedIcon />}
      showCancelButton={true}
      disableSqlHelp
      isTabView={false}
      onClose={closeDialog}
    />
  );
};

SwitchOverView.propTypes = {
  closeDialog: PropTypes.func.isRequired,
  leaderName: PropTypes.string.isRequired,
  replicaNames: PropTypes.arrayOf(
    PropTypes.shape({
      label: PropTypes.string.isRequired,
      value: PropTypes.string.isRequired,
    })
  ).isRequired,
  agentId: PropTypes.number.isRequired,
  patroniInstallationPath: PropTypes.string.isRequired,
  patroniConfigPath: PropTypes.string.isRequired,
};

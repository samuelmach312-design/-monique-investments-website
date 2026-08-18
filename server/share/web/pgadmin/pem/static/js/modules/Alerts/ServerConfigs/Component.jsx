///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState } from 'react';
import PropTypes from 'prop-types';
import getApiInstance from 'sources/api_instance';
import SchemaView from 'sources/SchemaView';
import { usePgAdmin } from 'sources/PgAdminProvider';
import url_for from 'sources/url_for';
import withPEMRoleCheck from 'sources/pem/helpers/withPEMRoleCheck';
import { transformData } from 'pem/modules/Alerts/ServerConfigs/utils';
import { ServerConfigCollectionSchema } from 'pem/modules/Alerts/ServerConfigs/serverConfigs.ui';
import { ENDPOINTS } from 'pem/common/constants';
import { MESSAGES } from 'pem/modules/Alerts/ServerConfigs/constants';

function ServerConfigs({ closeDialog }) {
  const pgAdmin = usePgAdmin();
  const api = getApiInstance();
  const serverConfigSchema = React.useRef(null);
  if (!serverConfigSchema.current) {
    serverConfigSchema.current = new ServerConfigCollectionSchema();
  }

  const [loadingMessage, setLoadingMessage] = useState('');

  const onSaveClick = (isNew, data) =>
    new Promise((resolve, reject) => {
      return api
        .post(
          url_for(ENDPOINTS.ALERTS.SERVER_CONFIG.UPDATE),
          data.server_config.changed
        )
        .then((res) => {
          pgAdmin.Browser.notifier.success(MESSAGES.SUCCESS);
          closeDialog();
          resolve(res.data);
        })
        .catch((err) => {
          pgAdmin.Browser.notifier.pgNotifier('error-noalert', err, '');
          reject(err);
        });
    });

  const fetchData = () => {
    return new Promise((resolve, reject) => {
      setLoadingMessage(MESSAGES.LOADING);
      api
        .get(url_for(ENDPOINTS.ALERTS.SERVER_CONFIG.FETCH))
        .then((res) => {
          const result = {
            server_config: transformData(res.data),
          };
          setLoadingMessage('');
          resolve(result);
        })
        .catch((err) => {
          console.error('Error fetching data:', err);
          reject(err);
        });
    });
  };

  const onHelp = () => {
    window.open(
      url_for(ENDPOINTS.HELP, {
        filename: ENDPOINTS.ALERTS.SERVER_CONFIG.HELP,
      })
    );
  };

  return (
    <SchemaView
      formType="dialog"
      getInitData={fetchData}
      loadingText={loadingMessage}
      viewHelperProps={{ mode: 'edit' }}
      schema={serverConfigSchema.current}
      showFooter={true}
      isTabView={false}
      onSave={onSaveClick}
      disableSqlHelp={true}
      onHelp={onHelp}
      onClose={closeDialog}
    />
  );
}
ServerConfigs.propTypes = {
  closeDialog: PropTypes.func,
};

export default withPEMRoleCheck(
  'pem_config',
  'Server configuration',
  ServerConfigs
);

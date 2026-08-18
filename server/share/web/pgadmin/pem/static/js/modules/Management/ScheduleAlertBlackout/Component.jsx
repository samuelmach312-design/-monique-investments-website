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
import { transformData } from 'pem/modules/Management/ScheduleAlertBlackout/utils';
import { BlackoutConfigCollectionSchema } from 'pem/modules/Management/ScheduleAlertBlackout/blackoutConfigs.ui';
import { ENDPOINTS } from 'pem/common/constants';
import { MESSAGES } from 'pem/modules/Management/ScheduleAlertBlackout/constants';

function BlackoutConfigs({ closeDialog }) {
  const pgAdmin = usePgAdmin();
  const api = getApiInstance();
  const BlackoutConfigschema = React.useRef(null);
  if (!BlackoutConfigschema.current) {
    BlackoutConfigschema.current = new BlackoutConfigCollectionSchema();
  }

  const [loadingMessage, setLoadingMessage] = useState('');

  const onSaveClick = (isNew, data) => {
    return new Promise((resolve, reject) => {
      api
        .post(url_for(ENDPOINTS.BLACKOUT.SAVE), data)
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
  };

  const fetchData = () => {
    return new Promise((resolve, reject) => {
      setLoadingMessage(MESSAGES.LOADING);
      api
        .get(url_for(ENDPOINTS.BLACKOUT.FETCH))
        .then((res) => {
          const result =
            transformData(res.data.data.result);
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
        filename: ENDPOINTS.BLACKOUT.HELP,
      })
    );
  };

  return (
    <SchemaView
      formType="dialog"
      getInitData={fetchData}
      loadingText={loadingMessage}
      viewHelperProps={{ mode: 'edit' }}
      schema={BlackoutConfigschema.current}
      showFooter={true}
      isTabView={true}
      onSave={onSaveClick}
      disableSqlHelp={true}
      onHelp={onHelp}
      onClose={closeDialog}
      confirmOnCloseReset={true}
    />
  );
}
BlackoutConfigs.propTypes = {
  closeDialog: PropTypes.func,
};

export default withPEMRoleCheck(
  'pem_config_alert',
  'Schedule Alert Blackout',
  BlackoutConfigs
);

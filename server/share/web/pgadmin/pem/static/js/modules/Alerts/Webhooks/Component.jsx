///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState } from 'react';
import PropTypes from 'prop-types';
import gettext from 'sources/gettext';
import getApiInstance from 'sources/api_instance';
import withPEMRoleCheck from 'sources/pem/helpers/withPEMRoleCheck';
import url_for from 'sources/url_for';
import SchemaView from 'sources/SchemaView';
import { WebhooksCollectionSchema } from './webhooksSchema.ui';
import { transformData } from './utils';
import { ENDPOINTS } from 'pem/common/constants';

function Webhooks() {
  const api = getApiInstance();
  const webHooksSchema = React.useRef(null);
  if (!webHooksSchema.current) {
    webHooksSchema.current = new WebhooksCollectionSchema();
  }

  const [loadingMessage, setLoadingMessage] = useState('');


  const fetchData = () => {
    return new Promise((resolve, reject) => {
      setLoadingMessage(gettext('Loading Webhooks...'));
      api
        .get(url_for(ENDPOINTS.ALERTS.WEBHOOKS.FETCH, { 'webhook_type': 'all' }))
        .then((res) => {
          const result = {
            webhook_alerts: transformData(res?.data.webhook_alerts),
          };
          setLoadingMessage('');
          resolve(result);
        })
        .catch((err) => {
          console.error(gettext('Error fetching data:'), err);
          reject(err);
        });
    });
  };

  return (
    <SchemaView
      formType="dialog"
      getInitData={fetchData}
      loadingText={loadingMessage}
      viewHelperProps={{ mode: 'edit' }}
      schema={webHooksSchema.current}
      showFooter={false}
      isTabView={false}
    />
  );
}

Webhooks.propTypes = {
  monitoringTarget: PropTypes.object,
};

export default withPEMRoleCheck(
  'pem_config',
  gettext('Webhooks'),
  Webhooks
);

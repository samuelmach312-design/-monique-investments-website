///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState } from 'react';
import gettext from 'sources/gettext';
import getApiInstance from 'sources/api_instance';
import url_for from 'sources/url_for';
import withPEMRoleCheck from 'sources/pem/helpers/withPEMRoleCheck';
import SchemaView from 'sources/SchemaView';
import { ENDPOINTS } from 'pem/common/constants';
import { transformData } from './utils';
import { AlertTemplateCollectionSchema } from './alertTemplatesSchema.ui';

function AlertTemplates() {
  
  const api = getApiInstance();
  const alertTemplateSchema = React.useRef(null);
  if (!alertTemplateSchema.current) {
    alertTemplateSchema.current = new AlertTemplateCollectionSchema();
  }

  const [loadingMessage, setLoadingMessage] = useState('');

  const fetchData = () => {
    return new Promise((resolve, reject) => {
      setLoadingMessage(gettext('Loading Custom Alerts...'));
      api
        .get(
          url_for(ENDPOINTS.ALERTS.TEMPLATES.FETCH)
        )
        .then((res) => {
          const result = {
            custom_alerts: transformData(res?.data.custom_alerts),
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
      schema={alertTemplateSchema.current}
      isTabView={false}
      showFooter={false}
    />
  );
}

export default withPEMRoleCheck(
  'pem_manage_alert',
  gettext('Alert Templates'),
  AlertTemplates
);

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
import SchemaView from 'sources/SchemaView';
import { ENDPOINTS } from 'pem/common/constants';
import { ProbeCollectionSchema } from './probesSchema.ui';
import { transformData } from './utils';

function CustomProbes() {
  const probesSchema = React.useRef(null);
  if (!probesSchema.current) {
    probesSchema.current = new ProbeCollectionSchema();
  }

  const api = getApiInstance();

  const [loadingMessage, setLoadingMessage] = useState('');

  const fetchData = () => {
    // Replace show_system_probe value with 1 to get all probes
    return new Promise((resolve, reject) => {
      setLoadingMessage(gettext('Loading probe configurations...'));
      api
        .get(
          url_for(ENDPOINTS.PROBES.CUSTOM_PROBES.FETCH, {
            show_system_probe: 1,
          })
        )
        .then((res) => {
          const result = {
            custom_probes: transformData(res.data.custom_probes),
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
      schema={probesSchema.current}
      addOnTop={true}
      showFooter={false}
      isTabView={false}
    />
  );
}

export default CustomProbes;

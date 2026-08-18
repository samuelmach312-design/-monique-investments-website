///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState, useEffect, useMemo, useCallback } from 'react';

import gettext from 'sources/gettext';
import getApiInstance from 'sources/api_instance';
import url_for from 'sources/url_for';
import SchemaView from 'sources/SchemaView';
import { useIsMounted } from 'sources/custom_hooks';
import withPEMRoleCheck from 'sources/pem/helpers/withPEMRoleCheck';
import { parseApiError } from 'sources/api_instance';

import { saveData } from 'pem/utils/actionFunctions';
import { fetchAllTemplates } from 'pem/modules/Charts/table/utils';
import { ENDPOINTS } from 'pem/common/constants';
import { AllPrivilegeTypes } from 'pem/common/constants';
import Loader from 'sources/components/Loader';
import { ProfilesCollectionSchema } from './manageProfileSchema.ui';
import {
  transformCreateAlertData,
  transformProbesData,
  transformProfileData,
  treatSavePayload,
} from './utils';

function ManageProfiles() {
  const checkIsMounted = useIsMounted();

  const [loadingMessage, setLoadingMessage] = useState(gettext('Loading profiles...'));
  const [refreshKey, setRefreshKey] = useState(0);
  const [isDataFetched, setIsDataFetched] = useState(false);

  const [schemaDependencies, setSchemaDependencies] = useState({
    probes: null,
    alerts: null,
    templates: null
  });

  const api = useMemo(() => getApiInstance(), []);

  const profileCollectionSchema = useMemo(() => {
    const { probes, alerts, templates } = schemaDependencies;
    
    if (!probes || !alerts || !templates) {
      return null;
    }
    return new ProfilesCollectionSchema(
      probes,
      alerts,
      templates
    );
  }, [schemaDependencies, refreshKey]);

  useEffect(() => {
    const fetchAllDependencies = async () => {
      try {
        const [probeRes, alertRes, templateRes] = await Promise.all([
          api.get(url_for(ENDPOINTS.PROBES.CUSTOM_PROBES.FETCH_LIGHT)),
          api.get(url_for(ENDPOINTS.ALERTS.TEMPLATES.FETCH_AUTO_CREATED_ALERTS)),
          fetchAllTemplates(true)
        ]);

        const transformedProbes = transformProbesData(probeRes.data.probes);
        const transformedAlerts = transformCreateAlertData(alertRes.data.custom_alerts);

        if (checkIsMounted()) {
          setSchemaDependencies({
            probes: transformedProbes.target_probe_configs,
            alerts: transformedAlerts,
            templates: templateRes
          });
        }
      } catch (err) {
        console.error(gettext('Error fetching schema dependencies:'), err);
      }
    };

    fetchAllDependencies();
  }, [api, checkIsMounted]); 

  const fetchData = useCallback(() => {
    return new Promise((resolve, reject) => {
      api
        .get(url_for(ENDPOINTS.PROFILES.FETCH))
        .then((res) => {
          const result = {
            manage_profiles: transformProfileData(res.data.data),
          };
          resolve(result);
          setIsDataFetched(true);
        })
        .catch((err) => {
          console.error(gettext('Error fetching data:'), err);
          setLoadingMessage(gettext('Some error while loading profiles...'));
          reject(err);
        });
    });
  }, [api]);

  useEffect(() => {
    if (profileCollectionSchema && isDataFetched) {
      setLoadingMessage('');
    }

  }, [profileCollectionSchema, isDataFetched]);

  const onProfileSave = useCallback((isChanged, changedData) => {
    if (isChanged && profileCollectionSchema?.state) {
      const schemaState = profileCollectionSchema.state;
      schemaState.isSaving = true;
      schemaState.setMessage(gettext('Saving profile...'));

      saveData(
        url_for(ENDPOINTS.PROFILES.SAVE),
        changedData.manage_profiles,
        gettext('Profile saved.'),
        treatSavePayload
      )
        .then(() => {
          setLoadingMessage(gettext('Loading profiles...'));
          setIsDataFetched(false); 
          setRefreshKey((prevKey) => prevKey + 1);
        })
        .catch((err) => {
          schemaState.setError({
            name: 'apierror',
            message: _.escape(parseApiError(err)),
          });
          setLoadingMessage('');
        })
        .finally(() => {
          if (checkIsMounted()) {
            schemaState.isSaving = false;
            schemaState.setMessage('');
          }
        });
    }
  }, [profileCollectionSchema, checkIsMounted]);

  if (!profileCollectionSchema) {
    return <Loader message={loadingMessage} />;
  }

  return (
    <SchemaView
      key={refreshKey}
      formType="dialog"
      getInitData={fetchData}
      onDataChange={onProfileSave}
      loadingText={loadingMessage}
      viewHelperProps={{ mode: 'edit' }}
      schema={profileCollectionSchema}
      showFooter={false}
      isTabView={false}
      disableSqlHelp={true}
      disableDialogHelp={true}
    />
  );
}

export default withPEMRoleCheck(
  AllPrivilegeTypes.MANAGE_PROFILES,
  'MANAGE PROFILES',
  ManageProfiles
);
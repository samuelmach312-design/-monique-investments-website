///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState, useEffect } from 'react';
import Grid from '@mui/material/Grid';
import { StyledSelect } from 'pem.charts/Common/StyledComponents';
import CloseSharpIcon from '@mui/icons-material/CloseSharp';
import SaveSharpIcon from '@mui/icons-material/SaveSharp';
import PropTypes from 'prop-types';
import {
  StyledConfigurationGrid,
  StyledPrimaryButton,
  StyledDefaultButton,
  StyledConfigurationFooterGrid,
  StyledSettingsFieldGrid,
  StyledSwitch,
  getCustomStyles,
  StyledSelectWrapper,
  StyledIconButton,
  CloseButtonContainer,
} from 'pem/modules/Monitoring/Common/StyledComponents';
import { handleAPIError } from 'pem/common/utils';
import {
  StyledInputLabel,
  StyledFormHelperText,
} from 'pem/common/StyledComponents';
import gettext from 'sources/gettext';
import getApiInstance from 'sources/api_instance';
import url_for from 'sources/url_for';
import { BreadcrumbConstants } from 'pem/modules/Monitoring/Common/constants';

const DashboardSharePermissions = ({
  currentSelection,
  setShowSharePermissions,
  refreshDashboardContent,
  showDashboardEditor,
  customDashboardSchema,
  setCustomDashboardSchema,
}) => {
  const [userGroups, setUserGroups] = useState([]);
  const [error, setError] = useState(false);

  const api = getApiInstance();

  const saveSharingPermissions = (payload) =>
    api
      .put(
        url_for(BreadcrumbConstants.SAVE_SHARE_PERMISSIONS_URL, {
          dashboard_id: payload.id,
        }),
        payload
      )
      .then(() => {})
      .catch((err) => handleAPIError(err));

  const getSharingPermissions = () =>
    api
      .get(
        url_for(BreadcrumbConstants.GET_SHARE_PERMISSIONS_URL, {
          dashboard_id: currentSelection.id,
        })
      )
      .then(({ data }) => {
        setCustomDashboardSchema((prev) => ({
          ...prev,
          shared_all: data?.shared_all,
          shared: data?.shared,
        }));
      })
      .catch((err) => handleAPIError(err));

  const fetchUserGroups = () => {
    api
      .get(url_for(BreadcrumbConstants.ROLE_LIST_URL))
      .then((res) => {
        setUserGroups(res?.data?.data);
      })
      .catch((err) => handleAPIError(err));
  };

  const validate = () => {
    const isValid =
      customDashboardSchema.shared_all ||
      customDashboardSchema.shared.length > 0;
    setError(!isValid);
    return isValid;
  };

  const handleChange = (values) => {
    setCustomDashboardSchema((prev) => ({
      ...prev,
      shared: values.map((val) => val.value),
    }));
    if (error && values.length > 0) {
      setError(false);
    }
  };

  useEffect(() => {
    fetchUserGroups();
    if (!showDashboardEditor) {
      getSharingPermissions();
    }
  }, []);

  return (
    <StyledConfigurationGrid
      container
      direction='column'
      alignItems='stretch'
      justifyContent='space-between'
      data-testid={'dashboard-settings-panel'}
      aria-label={BreadcrumbConstants.DASHBOARD_CONFIGURATION_PANEL}
      sx={{ width: '100%' }}
    >
      <CloseButtonContainer showDashboardEditor={showDashboardEditor}>
        <StyledIconButton
          variant='text'
          aria-haspopup='listbox'
          aria-controls='settings-menu'
          aria-label={gettext('Close Share Permissions Panel')}
          onClick={() => validate() && setShowSharePermissions(false)}
        >
          <CloseSharpIcon />
        </StyledIconButton>
      </CloseButtonContainer>
      <StyledSettingsFieldGrid container size={12} sx={{ width: '100%' }}>
        <span className='dashboardConfigurationHeading'>
          {gettext(
            'Specify the user groups that will have access to this dashboard.'
          )}
        </span>
      </StyledSettingsFieldGrid>
      <StyledSettingsFieldGrid container size={12} sx={{ width: '100%' }}>
        <Grid size={{ sm: 4, xs: 6 }}>
          <StyledInputLabel>
            {BreadcrumbConstants.SHARE_WITH_ALL}
          </StyledInputLabel>
        </Grid>
        <Grid size={{ sm: 8, xs: 6 }}>
          <StyledSwitch
            slotProps={{
              input: {
                'aria-label': BreadcrumbConstants.SHARE_WITH_ALL,
              },
            }}
            checked={customDashboardSchema.shared_all}
            onChange={() => {
              error && setError(false);
              setCustomDashboardSchema((prev) => ({
                ...prev,
                shared_all: !prev.shared_all,
                shared:
                  !prev.shared_all && prev.shared.length > 0 ? [] : prev.shared,
              }));
            }}
          />
        </Grid>
      </StyledSettingsFieldGrid>
      <StyledSettingsFieldGrid container size={12} sx={{ width: '100%' }}>
        <Grid size={{ sm: 4, xs: 12 }}>
          <StyledInputLabel>
            {BreadcrumbConstants.SHARE_WITH_ROLES}
          </StyledInputLabel>
        </Grid>
        <Grid size={{ sm: 8, xs: 12 }}>
          <StyledSelectWrapper>
            <StyledSelect
              isDisabled={customDashboardSchema.shared_all}
              isMulti
              defaultValue={[]}
              styles={getCustomStyles(error)}
              value={userGroups.filter((group) =>
                customDashboardSchema.shared.includes(group.value)
              )}
              options={userGroups}
              onChange={(selectedOption) => {
                handleChange(selectedOption);
              }}
              placeholder={gettext('Select from the list')}
              inputId='custom-select'
              aria-label='Select user roles'
            />
            <StyledFormHelperText variant='outlined' error={error}>
              {error ? gettext('Please select a user group') : ''}
            </StyledFormHelperText>
          </StyledSelectWrapper>
        </Grid>
      </StyledSettingsFieldGrid>
      {!showDashboardEditor && (
        <StyledConfigurationFooterGrid container sx={{ width: '100%' }}>
          <Grid>
            <StyledDefaultButton
              startIcon={<CloseSharpIcon />}
              onClick={() => setShowSharePermissions(false)}
              aria-label={BreadcrumbConstants.CANCEL_BUTTON}
            >
              {BreadcrumbConstants.CANCEL}
            </StyledDefaultButton>
          </Grid>
          <Grid>
            <StyledPrimaryButton
              startIcon={<SaveSharpIcon />}
              aria-label={BreadcrumbConstants.SAVE_BUTTON}
              onClick={() => {
                if (validate()) {
                  saveSharingPermissions({
                    id: currentSelection.id,
                    shared: customDashboardSchema.shared,
                    shared_all: customDashboardSchema.shared_all,
                  });
                  setTimeout(() => {
                    refreshDashboardContent();
                    setShowSharePermissions(false);
                  }, 50);
                }
              }}
            >
              {BreadcrumbConstants.APPLY}
            </StyledPrimaryButton>
          </Grid>
        </StyledConfigurationFooterGrid>
      )}
    </StyledConfigurationGrid>
  );
};
DashboardSharePermissions.propTypes = {
  currentSelection: PropTypes.object.isRequired,
  setShowSharePermissions: PropTypes.func.isRequired,
  refreshDashboardContent: PropTypes.func.isRequired,
  showDashboardEditor: PropTypes.bool.isRequired,
  customDashboardSchema: PropTypes.object.isRequired,
  setCustomDashboardSchema: PropTypes.func.isRequired,
};

export default DashboardSharePermissions;

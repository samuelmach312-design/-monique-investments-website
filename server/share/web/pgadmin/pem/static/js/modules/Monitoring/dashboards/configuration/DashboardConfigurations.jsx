///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState, useCallback, useContext } from 'react';
import { useTheme } from '@mui/material/styles';
import Grid from '@mui/material/Grid';
import CloseSharpIcon from '@mui/icons-material/CloseSharp';
import SaveSharpIcon from '@mui/icons-material/SaveSharp';
import CheckBoxOutlineBlankIcon from '@mui/icons-material/CheckBoxOutlineBlank';
import CheckBoxIcon from '@mui/icons-material/CheckBox';
import Checkbox from '@mui/material/Checkbox';
import PropTypes from 'prop-types';
import gettext from 'sources/gettext';
import { DefaultButton } from 'sources/components/Buttons';
import {
  StyledConfigurationGrid,
  StyledPrimaryButton,
  StyledConfigurationFooterGrid,
  StyledSettingsFieldGrid,
  StyledSwitch,
} from 'pem/modules/Monitoring/Common/StyledComponents';
import { StyledInputLabel } from 'pem/common/StyledComponents';
import SettingsTextField from 'pem/common/Textfields/SettingsTextField';
import getApiInstance from 'sources/api_instance';
import url_for from 'sources/url_for';
import {
  generateDashboardConfigBody,
  generateSettingsData,
} from 'pem/modules/Monitoring/Common/utils';
import { BreadcrumbConstants } from 'pem/modules/Monitoring/Common/constants';
import { DashboardSettingContext } from '../configuration/context';

const DashboardConfigurations = ({
  setShowSettings,
  dashboardSettings,
  refreshDashboardContent,
}) => {
  const [settingsData, setSettingsData] = useState(
    generateSettingsData(dashboardSettings?.settings)
  );
  const [errors, setErrors] = useState({
    historical_span_days_dashboard: false,
    historical_span_hours_dashboard: false,
  });
  const chartSettings = useContext(DashboardSettingContext);

  const theme = useTheme();

  const api = getApiInstance();

  const saveDashboardConfiguration = useCallback(
    (data) => {
      const dashboardConfig = generateDashboardConfigBody(data);
      return api
        .post(
          url_for(BreadcrumbConstants.DASHBOARD_SETTINGS_URL, {
            did: data.did,
          }),
          generateDashboardConfigBody(data)
        )
        .then(() => {
          chartSettings.setDashboardSettings({
            linked: dashboardConfig.linked,
            linked_span: dashboardConfig.linked_span,
            start: null,
            end: null,
          });
        })
        .catch((err) => {
          if (err?.response) {
            console.error('error resp', err?.response);
          } else if (err?.request) {
            console.error('error req', err?.request);
          } else if (err?.message) {
            console.error('error msg', err?.message);
          }
          console.error(err);
        });
    },
    [api, chartSettings]
  );

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
      <StyledSettingsFieldGrid container size={12} sx={{ width: '100%' }}>
        <span className='dashboardConfigurationHeading'>
          {gettext(
            'Dashboard configuration (Available for dashboards with line chart only)'
          )}
        </span>
      </StyledSettingsFieldGrid>
      <StyledSettingsFieldGrid container size={12} sx={{ width: '100%' }}>
        <Grid size={{ sm: 4, xs: 6 }}>
          <StyledInputLabel>
            {BreadcrumbConstants.LINK_TIMELINES}
          </StyledInputLabel>
        </Grid>
        <Grid size={{ sm: 8, xs: 6 }}>
          <StyledSwitch
            slotProps={{
              input: {
                'aria-label': BreadcrumbConstants.LINK_TIMELINES_ARIA_LABEL,
              },
            }}
            checked={settingsData?.link_timelines}
            onChange={() =>
              setSettingsData((prev) => ({
                ...prev,
                link_timelines: !prev?.link_timelines,
              }))
            }
          />
        </Grid>
      </StyledSettingsFieldGrid>
      <StyledSettingsFieldGrid container size={12} sx={{ width: '100%' }}>
        <SettingsTextField
          id='historical_span_days_dashboard'
          label={BreadcrumbConstants.HISTORICAL_SPAN_DAYS}
          value={settingsData?.historical_span_days_dashboard}
          setter={setSettingsData}
          errorSetter={setErrors}
          error={errors?.historical_span_days_dashboard}
          unit={BreadcrumbConstants.DAYS}
          min={0}
          max={365}
          disabled={!settingsData?.link_timelines}
        />
      </StyledSettingsFieldGrid>
      <StyledSettingsFieldGrid container size={12} sx={{ width: '100%' }}>
        <SettingsTextField
          id='historical_span_hours_dashboard'
          label={BreadcrumbConstants.HISTORICAL_SPAN_HOURS}
          value={settingsData?.historical_span_hours_dashboard}
          setter={setSettingsData}
          errorSetter={setErrors}
          error={errors?.historical_span_hours_dashboard}
          unit={BreadcrumbConstants.HOURS}
          min={0}
          max={23}
          disabled={!settingsData?.link_timelines}
        />
      </StyledSettingsFieldGrid>
      <StyledSettingsFieldGrid container size={12}>
        <Grid>
          <Checkbox
            icon={
              <CheckBoxOutlineBlankIcon
                htmlColor={theme.otherVars.checkbox.blank}
              />
            }
            checkedIcon={
              <CheckBoxIcon htmlColor={theme.palette.primary.main} />
            }
            inputProps={{
              'aria-label': BreadcrumbConstants.REMEMBER_CONFIGURATION,
            }}
            checked={settingsData?.remember_configuration}
            onChange={() =>
              setSettingsData((prev) => ({
                ...prev,
                remember_configuration: !prev?.remember_configuration,
              }))
            }
          />
        </Grid>
        <Grid alignContent='center'>
          <StyledInputLabel custom_margin={0}>
            {BreadcrumbConstants.REMEMBER_CONFIGURATION}
          </StyledInputLabel>
        </Grid>
      </StyledSettingsFieldGrid>
      <StyledConfigurationFooterGrid container sx={{ width: '100%' }}>
        <Grid>
          <DefaultButton
            startIcon={<CloseSharpIcon />}
            onClick={() => setShowSettings(false)}
            aria-label={BreadcrumbConstants.CANCEL_BUTTON}
          >
            {BreadcrumbConstants.CANCEL}
          </DefaultButton>
        </Grid>
        <Grid>
          <StyledPrimaryButton
            startIcon={<SaveSharpIcon />}
            disabled={Object.values(errors).some((error) => error)}
            aria-label={BreadcrumbConstants.SAVE_BUTTON}
            onClick={() => {
              saveDashboardConfiguration({
                ...settingsData,
                did: dashboardSettings?.context?.did,
              });
              setTimeout(() => {
                refreshDashboardContent();
                setShowSettings(false);
              }, 50);
            }}
          >
            {BreadcrumbConstants.APPLY}
          </StyledPrimaryButton>
        </Grid>
      </StyledConfigurationFooterGrid>
    </StyledConfigurationGrid>
  );
};
DashboardConfigurations.propTypes = {
  setShowSettings: PropTypes.func.isRequired,
  dashboardSettings: PropTypes.object.isRequired,
  refreshDashboardContent: PropTypes.func.isRequired,
};

export default DashboardConfigurations;

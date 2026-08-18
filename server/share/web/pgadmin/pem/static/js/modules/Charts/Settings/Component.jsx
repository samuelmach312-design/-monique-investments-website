///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, {
  useState,
  useEffect,
  forwardRef,
  useImperativeHandle,
} from 'react';
import Grid from '@mui/material/Grid';
import _ from 'lodash';
import PropTypes from 'prop-types';
import getApiInstance from 'sources/api_instance';
import url_for from 'sources/url_for';
import {
  areObjectsEqual,
  areArraysEqual,
  shouldDisableSave,
  generateSettingsPayload,
} from 'pem.charts/Common/utils';
import { handleError } from 'pem/common/utils';
import gettext from 'sources/gettext';
import {
  CHART_CONSTANTS,
  initSettingsData,
  initSettingsError,
  downloadFormatOptions,
} from 'pem.charts/Common/constants';
import { ColorButton } from 'pem.charts/Common/Buttons/ColorButton';
import {
  CHART_TYPE,
  DEFAULT_BAR_CHART_COLORS,
  DEFAULT_CHART_COLORS,
} from 'pem/common/constants';
import CustomPropTypes from 'pem/utils/custom_prop_types';
import ChartSettingsInputField from 'pem/common/Textfields/ChartSettingsInputField';
import {
  StyledSettingsComponent,
  StyledSelect,
  StyledSecondaryLabel,
} from 'pem.charts/Common/StyledComponents';
import { StyledInputLabel } from 'pem/common/StyledComponents';

const SettingsDialog = forwardRef(
  (
    {
      openSettings,
      setOpenSettings,
      colors,
      setColors,
      chartProperties,
      setDisableSave,
    },
    ref
  ) => {
    const [settingsData, setSettingsData] = useState(initSettingsData);
    const [originalSettingsData, setOriginalSettingsData] =
      useState(initSettingsData);
    const [defaultColors, setDefaultColors] = useState([]);
    const [errors, setErrors] = useState(initSettingsError);
    const api = getApiInstance();

    const handleSaveSettings = () => {
      api
        .put(
          url_for(chartProperties.endpoints.settings, {
            ...chartProperties.metadata,
          }),
          generateSettingsPayload(settingsData, colors)
        )
        .then(() => {
          setOpenSettings((prev) => !prev);
        })
        .catch((errorResponse) => {
          handleError(errorResponse, chartProperties);
        });
    };

    const handleFetchSettings = () => {
      api
        .get(
          url_for(chartProperties.endpoints.settings, {
            ...chartProperties.metadata,
          })
        )
        .then((res) => {
          const data = res?.data?.data;
          const processedSettingsData = {
            auto_refresh: Number(data?.timeout),
            historical_span_days: Math.floor(Number(data?.span) / 24),
            historical_span_hours: Math.floor(Number(data?.span) % 24),
            data_points: data?.points,
            download_format: data?.downloadformat,
          };
          setSettingsData(processedSettingsData);
          setOriginalSettingsData(processedSettingsData);
          setDefaultColors(colors);
        })
        .catch((errorResponse) => {
          handleError(errorResponse, chartProperties);
        });
    };

    useEffect(() => {
      openSettings && handleFetchSettings();
    }, [openSettings]);

    useEffect(() => {
      if (
        areObjectsEqual(settingsData, originalSettingsData) &&
        areArraysEqual(colors, defaultColors) &&
        shouldDisableSave(errors)
      ) {
        setDisableSave(true);
      } else {
        setDisableSave(false);
      }
    }, [settingsData, colors, defaultColors]);

    useImperativeHandle(ref, () => ({
      settings: handleSaveSettings,
      resetSettings: () => {
        setSettingsData(initSettingsData);
        if (chartProperties.chart.type === CHART_TYPE.B) {
          setColors(DEFAULT_BAR_CHART_COLORS);
        } else if (
          chartProperties.chart.type === CHART_TYPE.L ||
          chartProperties.chart.type === CHART_TYPE.P ||
          chartProperties.chart.type === CHART_TYPE.CL
        ) {
          setColors(
            _.map(colors, (item, index) => ({
              ...item,
              color: DEFAULT_CHART_COLORS[index] || item.color,
            }))
          );
        }
      },
    }));

    return (
      <StyledSettingsComponent
        openSettings={openSettings}
        data-testid='settingsContainer'
      >
        <div className='inputContainer'>
          <Grid container size={12} gap={1} sx={{ width: '100%' }}>
            <Grid size={{ sm: 4, xs: 12 }}>
              <StyledInputLabel>
                {gettext(CHART_CONSTANTS.AUTO_REFRESH)}
              </StyledInputLabel>
              <StyledSecondaryLabel>
                {gettext(CHART_CONSTANTS.AUTO_REFRESH_RANGE)}
              </StyledSecondaryLabel>
            </Grid>
            <ChartSettingsInputField
              id={CHART_CONSTANTS.AUTO_REFRESH_ID}
              label={CHART_CONSTANTS.AUTO_REFRESH}
              value={settingsData?.auto_refresh}
              setter={setSettingsData}
              errorSetter={setErrors}
              error={errors?.auto_refresh}
              unit={CHART_CONSTANTS.SECONDS}
              min={10}
              max={7200}
            />
          </Grid>
          {(chartProperties.chart.type === CHART_TYPE.L ||
            chartProperties.chart.type === CHART_TYPE.CL) && (
            <>
              <Grid container size={12} gap={1} sx={{ width: '100%' }}>
                <Grid size={{ sm: 4, xs: 12 }}>
                  <StyledInputLabel>
                    {gettext(CHART_CONSTANTS.HISTORICAL_SPAN)}
                  </StyledInputLabel>
                  <StyledSecondaryLabel>
                    {gettext(CHART_CONSTANTS.HISTORICAL_SPAN_RANGE)}
                  </StyledSecondaryLabel>
                </Grid>
                <ChartSettingsInputField
                  id={CHART_CONSTANTS.SPAN_DAYS_ID}
                  label={CHART_CONSTANTS.SPAN_DAYS}
                  value={settingsData?.historical_span_days}
                  setter={setSettingsData}
                  errorSetter={setErrors}
                  error={errors?.historical_span_days}
                  noMargin={true}
                  unit={CHART_CONSTANTS.DAYS}
                  min={0}
                  max={365}
                />
                <ChartSettingsInputField
                  id={CHART_CONSTANTS.SPAN_HOURS_ID}
                  label={CHART_CONSTANTS.SPAN_HOURS}
                  value={settingsData?.historical_span_hours}
                  setter={setSettingsData}
                  errorSetter={setErrors}
                  error={errors?.historical_span_hours}
                  noMargin={true}
                  unit={CHART_CONSTANTS.HOURS}
                  min={0}
                  max={23}
                />
              </Grid>
              <Grid container size={12} gap={1} sx={{ width: '100%' }}>
                <Grid size={{ sm: 4, xs: 12 }}>
                  <StyledInputLabel>
                    {gettext(CHART_CONSTANTS.DATA_POINTS)}
                  </StyledInputLabel>
                  <StyledSecondaryLabel>
                    {gettext(CHART_CONSTANTS.DATA_POINTS_RANGE)}
                  </StyledSecondaryLabel>
                </Grid>
                <ChartSettingsInputField
                  id={CHART_CONSTANTS.DATA_POINTS_ID}
                  label={CHART_CONSTANTS.DATA_POINTS}
                  value={settingsData?.data_points}
                  setter={setSettingsData}
                  errorSetter={setErrors}
                  error={errors?.data_points}
                  unit={CHART_CONSTANTS.POINTS}
                  min={20}
                  max={300}
                />
              </Grid>
            </>
          )}
          {[CHART_TYPE.L, CHART_TYPE.P, CHART_TYPE.B, CHART_TYPE.CL].includes(
            chartProperties.chart.type
          ) && (
            <>
              <Grid container size={12} sx={{ width: '100%' }}>
                <Grid size={4}>
                  <StyledInputLabel
                    aria-label={gettext(CHART_CONSTANTS.DOWNLOAD_FORMAT)}
                  >
                    {gettext(CHART_CONSTANTS.DOWNLOAD_FORMAT)}
                  </StyledInputLabel>
                </Grid>
                <Grid size={8}>
                  <StyledSelect
                    className='basic-single'
                    id={CHART_CONSTANTS.DOWNLOAD_FORMAT_ID}
                    data-testid={CHART_CONSTANTS.DOWNLOAD_FORMAT_ID}
                    classNamePrefix='select'
                    value={downloadFormatOptions.find(
                      (option) => option.value === settingsData.download_format
                    )}
                    name='Download Format'
                    options={downloadFormatOptions}
                    onChange={(selectedOption) =>
                      setSettingsData((prev) => ({
                        ...prev,
                        download_format: selectedOption?.value,
                      }))
                    }
                  />
                </Grid>
              </Grid>
              <Grid container size={12} sx={{ width: '100%' }}>
                <Grid size={4} container>
                  <StyledInputLabel
                    aria-label={gettext(CHART_CONSTANTS.COLORS)}
                  >
                    {gettext(CHART_CONSTANTS.COLORS)}
                  </StyledInputLabel>
                </Grid>
                <Grid size={8} container>
                  <Grid container size={12} sx={{ width: '100%' }}>
                    {_.map(colors, (item, i) => (
                      <Grid size={6} key={i} container>
                        <ColorButton
                          label={item?.label}
                          value={item?.color}
                          options={{
                            allowSave: true,
                            input: true,
                          }}
                          onSave={(color, label) => {
                            setColors((prev) =>
                              prev.map((ele) => {
                                if (ele?.label === label) {
                                  return {
                                    label,
                                    color,
                                  };
                                } else {
                                  return ele;
                                }
                              })
                            );
                          }}
                        />
                      </Grid>
                    ))}
                  </Grid>
                </Grid>
              </Grid>
            </>
          )}
        </div>
      </StyledSettingsComponent>
    );
  }
);

SettingsDialog.displayName = 'Settings';
SettingsDialog.propTypes = {
  openSettings: PropTypes.bool.isRequired,
  setOpenSettings: PropTypes.func.isRequired,
  colors: PropTypes.array.isRequired,
  setColors: PropTypes.func.isRequired,
  chartProperties: CustomPropTypes.chartProp,
  setDisableSave: PropTypes.func.isRequired,
};

export default SettingsDialog;

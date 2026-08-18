///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { forwardRef, useState, useRef } from 'react';
import DescriptionIcon from '@mui/icons-material/Description';
import GetAppIcon from '@mui/icons-material/GetApp';
import CachedIcon from '@mui/icons-material/Cached';
import ListIcon from '@mui/icons-material/List';
import FullscreenIcon from '@mui/icons-material/Fullscreen';
import CloseIcon from '@mui/icons-material/Close';
import RestartAltIcon from '@mui/icons-material/RestartAlt';
import SaveIcon from '@mui/icons-material/Save';
import SettingsIcon from '@mui/icons-material/Settings';
import Grid from '@mui/material/Grid';
import PropTypes from 'prop-types';
import {
  handleGraphDownload,
  getChartOffsetWidth,
} from 'pem.charts/Common/utils';
import { generateRandomNumber } from 'pem/common/utils';
import MarkdownParser from 'pem/modules/Monitoring/Common/MarkdownParser';
import gettext from 'sources/gettext';
import { CHART_CONSTANTS, ChartWidth } from 'pem.charts/Common/constants';
import { StyledWarningIcon } from 'pem/common/StyledComponents';
import { TABLE_CHART_TYPE_VALUES } from 'pem/common/constants';
import SettingsDialog from 'pem.charts/Settings/Component';
import ChartButton from 'pem.charts/Common/Buttons/ChartButton';
import {
  StyledContainer,
  StyledTooltip,
} from 'pem.charts/Common/StyledComponents';
import { ChartErrorIcon } from 'pem/common/StyledComponents';
import UplotLegend from 'pem.charts/Common/Legends/UplotLegend';
import CustomPropTypes from 'pem/utils/custom_prop_types';

const ChartContainer = forwardRef((props, ref) => {
  const {
    title,
    refresh,
    colors,
    setColors,
    chartProperties,
    series,
    error,
    downloadFormat } =
    props;
  const { chartContainerRef, uplotRef } = ref;

  const [isFullScreen, setIsFullScreen] = useState(false);
  const [downloading, setDownloading] = useState(false);
  const [openSettings, setOpenSettings] = useState(false);
  const [disableSave, setDisableSave] = useState(false);
  const cardTitle = openSettings
    ? gettext(CHART_CONSTANTS.CHART_SETTING_TITLE)
    : title;

  const settingsRef = useRef(null);
  const chartId = CHART_CONSTANTS.CHART_MAIN_CONTAINER + generateRandomNumber();
  return (
    <>
      <Grid
        size={ChartWidth[chartProperties?.layout?.width]}
        offset={getChartOffsetWidth(
          chartProperties?.layout?.align,
          chartProperties?.layout?.width
        )}
      >
        <StyledContainer
          isFullScreen={isFullScreen}
          id={chartId}
          isTableChart={TABLE_CHART_TYPE_VALUES.includes(
            chartProperties.chart.type
          )}
          data-testid={chartId}
        >
          <div className='cardHeader'>
            <div className='cardTitle' aria-label={cardTitle}>
              {error?.errorMessage && (
                <StyledTooltip
                  title={error.errorMessage}
                  aria-label={error.errorMessage}
                  disableInteractive={false}
                >
                  {error?.serverError ? (
                    <StyledWarningIcon />
                  ) : (
                    <ChartErrorIcon success={error.success} />
                  )}
                </StyledTooltip>
              )}{' '}
              {cardTitle}
            </div>
            {!downloading && (
              <div className='buttons' data-testid='buttons'>
                <ChartButton
                  title={
                    <MarkdownParser
                      description={chartProperties.chart.description}
                    />
                  }
                  Icon={DescriptionIcon}
                  openSettings={openSettings}
                  id={CHART_CONSTANTS.DESCRIPTION}
                />
                <ChartButton
                  title={CHART_CONSTANTS.REFRESH}
                  Icon={CachedIcon}
                  clickAction={() => refresh()}
                  openSettings={openSettings}
                  id={CHART_CONSTANTS.REFRESH}
                />
                <ChartButton
                  title={CHART_CONSTANTS.SETTINGS}
                  Icon={SettingsIcon}
                  clickAction={() => setOpenSettings((prev) => !prev)}
                  openSettings={openSettings}
                  id={CHART_CONSTANTS.SETTINGS}
                />
                {!TABLE_CHART_TYPE_VALUES.includes(
                  chartProperties.chart.type
                ) && (
                  <>
                    <ChartButton
                      title={CHART_CONSTANTS.DOWNLOAD}
                      id={CHART_CONSTANTS.DOWNLOAD}
                      Icon={GetAppIcon}
                      openSettings={openSettings}
                      clickAction={() =>
                        handleGraphDownload(
                          chartId, title, setDownloading, downloadFormat
                        )
                      }
                    />
                    <ChartButton
                      title={
                        <UplotLegend
                          series={series}
                          chartType={chartProperties.chart.type}
                          ref={uplotRef}
                        />
                      }
                      Icon={ListIcon}
                      openSettings={openSettings}
                      id={CHART_CONSTANTS.LEGEND}
                    />
                    <ChartButton
                      title={
                        isFullScreen
                          ? CHART_CONSTANTS.EXIT_FULLSCREEN
                          : CHART_CONSTANTS.FULLSCREEN
                      }
                      Icon={isFullScreen ? CloseIcon : FullscreenIcon}
                      clickAction={() => setIsFullScreen((prev) => !prev)}
                      openSettings={openSettings}
                      id={CHART_CONSTANTS.FULLSCREEN}
                    />
                  </>
                )}
                <ChartButton
                  title={CHART_CONSTANTS.RESET_TO_DEFAULT}
                  id={CHART_CONSTANTS.RESET}
                  Icon={RestartAltIcon}
                  clickAction={() => {
                    if (settingsRef.current) {
                      settingsRef.current?.resetSettings();
                    }
                  }}
                  openSettings={!openSettings}
                />
                <ChartButton
                  title={CHART_CONSTANTS.SAVE}
                  id={CHART_CONSTANTS.SAVE}
                  Icon={SaveIcon}
                  clickAction={() => {
                    if (settingsRef.current) {
                      settingsRef.current?.settings();
                      refresh();
                    }
                  }}
                  openSettings={!openSettings}
                  disable={disableSave}
                />
                <ChartButton
                  title={CHART_CONSTANTS.CLOSE}
                  id={CHART_CONSTANTS.CLOSE}
                  Icon={CloseIcon}
                  clickAction={() => setOpenSettings((prev) => !prev)}
                  openSettings={!openSettings}
                />
              </div>
            )}
          </div>
          <div ref={chartContainerRef} className='chartContainer'>
            <SettingsDialog
              openSettings={openSettings}
              setOpenSettings={setOpenSettings}
              setDisableSave={setDisableSave}
              colors={colors}
              setColors={setColors}
              ref={settingsRef}
              chartProperties={chartProperties}
            />
            {props.children}
          </div>
        </StyledContainer>
      </Grid>
    </>
  );
});

ChartContainer.displayName = 'ChartContainer';
ChartContainer.propTypes = {
  title: PropTypes.string.isRequired,
  refresh: PropTypes.func.isRequired,
  colors: PropTypes.array.isRequired,
  setColors: PropTypes.func.isRequired,
  chartProperties: CustomPropTypes.chartProp,
  series: CustomPropTypes.uplotSeriesProp,
  children: CustomPropTypes.children,
  error: PropTypes.object,
  downloadFormat: PropTypes.oneOf([1, 2]),
};

export default ChartContainer;

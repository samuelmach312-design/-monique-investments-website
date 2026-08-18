///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import Grid from '@mui/material/Grid';
import gettext from 'sources/gettext';
import {
  ChartConfig,
  StyledDefaultButton,
  StyledToggleButton,
  LineChart,
  BarChart,
  PieChart,
  TableChart,
  ChartPlaceholderWrapper,
  ChartPlaceholderHeader,
  ChartPlaceholderTitle,
  ChartPlaceholderName,
  Delete,
  ToggleLayout,
  ToggleTitle,
  ChartPlaceholderDescription,
  StyledToggleButtonGroup,
} from 'pem/modules/Monitoring/Common/StyledComponents';
import { StyledTooltip } from 'pem.charts/Common/StyledComponents';
import {
  deleteChart,
  chartWidthHandler,
  chartAlignmentHandler,
} from 'pem/modules/Monitoring/Common/utils';
import MarkdownParser from 'pem/modules/Monitoring/Common/MarkdownParser';
import {
  BreadcrumbConstants,
  chartWidthToGridColumns,
} from 'pem/modules/Monitoring/Common/constants';

const AddChart = ({ chartInfo, sectionID, setCustomDashboardSchema }) => {
  const getChartIcon = (chartType) => {
    const icons = {
      L: <LineChart />,
      B: <BarChart />,
      P: <PieChart />,
    };

    return icons[chartType] || <TableChart />;
  };

  const isNotTable = ['B', 'P', 'L'].includes(chartInfo?.chart_type.trim());
  return (
    <Grid
      size={
        Number(chartInfo.chart_align) === 2
          ? 12
          : chartWidthToGridColumns[Number(chartInfo.chart_size)]
      }
      display='flex'
      justifyContent={
        Number(chartInfo.chart_align) === 1
          ? 'flex-start'
          : Number(chartInfo.chart_align) === 2
            ? 'center'
            : 'flex-end'
      }
    >
      <ChartPlaceholderWrapper
        calculatedwidth={
          Number(chartInfo.chart_align) === 2
            ? chartWidthToGridColumns[Number(chartInfo.chart_size)] * 8.33 + '%'
            : '100%'
        }
        data-testid='chart-placeholder'
      >
        <ChartConfig>
          <ChartPlaceholderHeader>
            <ChartPlaceholderTitle>
              {getChartIcon(chartInfo?.chart_type.trim())}
              <ChartPlaceholderName
                aria-label={gettext(chartInfo?.chart_title)}
              >
                {gettext(chartInfo?.chart_title)}
              </ChartPlaceholderName>
            </ChartPlaceholderTitle>
            <StyledDefaultButton
              startIcon={<Delete />}
              aria-label={BreadcrumbConstants.DELETE}
              onClick={() =>
                deleteChart(
                  setCustomDashboardSchema,
                  sectionID,
                  chartInfo?.chart_id
                )
              }
            >
              {BreadcrumbConstants.DELETE}
            </StyledDefaultButton>
          </ChartPlaceholderHeader>
          <ToggleLayout
            container
            spacing={1}
            alignItems='center'
            sx={{ width: '100%' }}
          >
            <Grid size={3}>
              <ToggleTitle>{gettext('Chart width')}</ToggleTitle>
            </Grid>
            <Grid size={3}>
              <StyledToggleButtonGroup
                value={Number(chartInfo?.chart_size)}
                exclusive
                onChange={(e, val) => {
                  if (val !== null) {
                    chartWidthHandler(
                      setCustomDashboardSchema,
                      sectionID,
                      chartInfo?.chart_id,
                      val
                    );
                  }
                }}
                aria-label={gettext('chart width')}
              >
                <StyledToggleButton
                  value={1}
                  aria-label={gettext('quarter width chart')}
                  disabled={!isNotTable}
                >
                  {gettext('33%')}
                </StyledToggleButton>
                <StyledToggleButton
                  value={2}
                  aria-label={gettext('half width chart')}
                >
                  {gettext('50%')}
                </StyledToggleButton>
                <StyledToggleButton
                  value={3}
                  aria-label={gettext('three quarter width chart')}
                  disabled={!isNotTable}
                >
                  {gettext('66%')}
                </StyledToggleButton>
                <StyledToggleButton
                  value={6}
                  aria-label={gettext('full width chart')}
                >
                  {gettext('100%')}
                </StyledToggleButton>
              </StyledToggleButtonGroup>
            </Grid>
          </ToggleLayout>
          <ToggleLayout container spacing={1} alignItems='center'>
            <Grid size={3}>
              <ToggleTitle>{gettext('Chart alignment')}</ToggleTitle>
            </Grid>
            <Grid size={3}>
              <StyledToggleButtonGroup
                value={Number(chartInfo?.chart_align)}
                exclusive
                onChange={(e, val) => {
                  if (val !== null) {
                    chartAlignmentHandler(
                      setCustomDashboardSchema,
                      sectionID,
                      chartInfo?.chart_id,
                      val
                    );
                  }
                }}
                aria-label={gettext('chart alignment')}
              >
                <StyledToggleButton
                  value={1}
                  aria-label={gettext('left aligned')}
                  disabled={!isNotTable}
                >
                  {gettext('Left')}
                </StyledToggleButton>
                <StyledToggleButton value={2} aria-label={gettext('centered')}>
                  {gettext('Center')}
                </StyledToggleButton>
              </StyledToggleButtonGroup>
            </Grid>
          </ToggleLayout>
          <StyledTooltip
            title={<MarkdownParser description={chartInfo?.chart_descp} />}
            aria-label='Chart description'
          >
            <ChartPlaceholderDescription>
              <MarkdownParser description={chartInfo?.chart_descp} />
            </ChartPlaceholderDescription>
          </StyledTooltip>
        </ChartConfig>
      </ChartPlaceholderWrapper>
    </Grid>
  );
};

AddChart.propTypes = {
  chartInfo: PropTypes.object.isRequired,
  sectionID: PropTypes.number.isRequired,
  setCustomDashboardSchema: PropTypes.func.isRequired,
};

export default AddChart;

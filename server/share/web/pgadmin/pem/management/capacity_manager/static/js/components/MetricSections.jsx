///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useRef, useMemo, useState, forwardRef } from 'react';
import UplotReact from 'uplot-react';
import { useResizeDetector } from 'react-resize-detector';
import PropTypes from 'prop-types';

import {
  Accordion,
  AccordionSummary,
  AccordionDetails,
  Typography,
  Stack,
  Tooltip,
} from '@mui/material';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import { useTheme } from '@mui/material/styles';
import 'uplot/dist/uPlot.min.css';
import { handleOpts } from '../utils';
import {
  StyledChartContainer,
  StyledAccordionContainer,
  LegendContainer,
  LegendItem,
  StyledWarningIcon,
  ChartErrorIcon,
  StyledErrorDiv
} from './StyledComponents';
import { MinimalisticPgTable } from './MinimalistPgTable';
import { parseChartData, transformDataForTable } from '../utils';

const MetricesSection = forwardRef(({ data, reportMetadata }, ref) => {
  const uplotRef = useRef();
  const theme = useTheme();

  const { chart_style, chart_type } = reportMetadata;
  const { width, height, ref: chartContainerRef } = useResizeDetector();

  const { columns, rows, errorMessage, allMetricEmpty } = useMemo(
    () => transformDataForTable(data, chart_style),
    [data, chart_style]
  );
  const { plotData, plotSeries } = useMemo(() => parseChartData(data), [data]);

  const [activeSeries, setActiveSeries] = useState(
    Array(plotSeries.length).fill(true)
  );
  const [liveValues, setLiveValues] = useState(
    Array(plotSeries.length).fill(null)
  );

  const toggleSeries = (index) => {
    setActiveSeries((prev) => {
      const updatedSeries = [...prev];
      updatedSeries[index] = !updatedSeries[index];
      return updatedSeries;
    });
  };

  const handleChartCreate = (chart) => {
    uplotRef.current = chart;

    const updateLiveValues = () => {
      const { idx } = chart.cursor;
      if (idx == null) {
        setLiveValues(Array(chart.series.length).fill('--'));
        return;
      }

      setLiveValues(
        chart.data.map((series) => {
          if (!series || !series.length) return '--';
          const value = series[idx];
          return value !== undefined || value !== null ? value : '--';
        })
      );
    };

    chart.root.addEventListener('mousemove', updateLiveValues);
  };

  const filteredPlotData = useMemo(() => {
    return plotData.map((series, index) =>
      index === 0 || activeSeries[index] ? series : series.map(() => null)
    );
  }, [plotData, activeSeries]);

  const options = useMemo(
    () => handleOpts(width, height, plotSeries, '', '', theme),
    [width, height, plotSeries, theme]
  );
  return (
    <div ref={ref}>
      <Accordion defaultExpanded>
        <AccordionSummary expandIcon={<ExpandMoreIcon />}>
          <Typography variant="h6">
            {errorMessage && (
              <Tooltip
                title={errorMessage}
                aria-label={errorMessage}
                disableInteractive={false}
              >
                {allMetricEmpty ? (
                  <StyledWarningIcon />
                ) : (
                  <ChartErrorIcon success={allMetricEmpty} />
                )}
              </Tooltip>
            )}{' '}{data.label}
          </Typography>
        </AccordionSummary>
        <AccordionDetails>
          {allMetricEmpty?(
            <StyledErrorDiv>
              <span>
                {errorMessage}
              </span>
            </StyledErrorDiv>
          ):(
            <StyledAccordionContainer>
              <Stack spacing={2}>
                {[0, 2].includes(chart_type) && (
                  <StyledChartContainer ref={chartContainerRef}>
                    <UplotReact
                      target={chartContainerRef.current}
                      options={options}
                      data={filteredPlotData}
                      onCreate={handleChartCreate}
                    />
                  </StyledChartContainer>
                )}

                <LegendContainer>
                  {plotSeries.map((serie, index) => (
                    <LegendItem
                      key={index}
                      color={index === 0 ? 'transparent' : serie.stroke}
                      active={index === 0 ? true : activeSeries[index]}
                      onClick={index === 0 || serie.error? null : () => toggleSeries(index)}
                    >
                      {index !== 0 && <span className="legend-color-box"></span>}{' '}
                      {!serie.error?(<><strong>{serie.label}</strong>:&nbsp;</>):(
                        <strong style={{ color: theme.palette.text.disabled }}>
                          {serie.label}
                        </strong>
                      )}
                      {index === 0 && liveValues[index] !== '--'
                        ? new Date(liveValues[index])
                          .toISOString()
                          .replace('T', ' ')
                          .slice(0, 19)
                        : liveValues[index] ?? '--'}
                    </LegendItem>
                  ))}
                </LegendContainer>

                {[1, 2].includes(chart_type) && (
                  <MinimalisticPgTable
                    columns={columns}
                    data={rows}
                    showFooter={false}
                  />
                )}
              </Stack>
            </StyledAccordionContainer>)}
        </AccordionDetails>
      </Accordion>
    </div>
  );
});

MetricesSection.propTypes = {
  data: PropTypes.oneOfType([
    PropTypes.arrayOf(
      PropTypes.shape({
        node_data: PropTypes.object,
        node_type: PropTypes.oneOf(['metrics', 'submetrics']),
        inode: PropTypes.bool,
        label: PropTypes.string,
        pdata: PropTypes.object,
      })
    ),
    PropTypes.shape({
      node_data: PropTypes.object,
      node_type: PropTypes.oneOf(['metrics', 'submetrics']),
      inode: PropTypes.bool,
      label: PropTypes.string,
      pdata: PropTypes.object,
    }),
  ]).isRequired,

  reportMetadata: PropTypes.shape({
    title: PropTypes.string,
    dateGenerated: PropTypes.string,
    author: PropTypes.string,
    chart_type: PropTypes.number,
    chart_style: PropTypes.number,
  }).isRequired,
};

MetricesSection.displayName = 'MetricesSection';

export default MetricesSection;

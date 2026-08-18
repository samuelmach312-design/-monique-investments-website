///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useEffect, useState, useRef, useContext } from 'react';
import { Chart } from 'chart.js';
import { useTheme } from '@mui/material/styles';
import { useResizeDetector } from 'react-resize-detector';
import PropTypes from 'prop-types';
import UplotReact from 'uplot-react';
import { PieChart } from 'sources/chartjs';
import url_for from 'sources/url_for';
import Loader from 'sources/components/Loader';
import getApiInstance from 'sources/api_instance';
import CustomPropTypes from 'pem/utils/custom_prop_types';
import ChartContainer from 'pem.charts/chart_container/ChartContainer';
import PgTable from 'sources/components/PgTable';
import NestedTable from 'pem.charts/table/NestedTable';
import {
  StyledErrorDiv,
  EnableProbeLink,
} from 'pem.charts/Common/StyledComponents';
import {
  handleOpts,
  handleSeries,
  transformSeriesData,
  handleColors,
} from 'pem.charts/Common/utils';
import { transformTableColumns } from 'pem.charts/table/utils';
import { handleError } from 'pem/common/utils';
import {
  CHART_CONSTANTS,
  NESTED_TABLE_TABS,
} from 'pem.charts/Common/constants';
import { CHART_TYPE, TABLE_CHART_TYPE_VALUES } from 'pem/common/constants';
import sideLabelPlugin from 'pem.charts/Common/plugins/sideLabelPlugin';
import { DashboardSettingContext } from 'pem/modules/Monitoring/dashboards/configuration/context';

const DashboardChart = (props) => {
  const { width, height, ref: chartContainerRef } = useResizeDetector();
  const { chartProperties, addToQueue, setCurrentSelection, probeDisabled } =
    props;
  const api = getApiInstance();

  const [chartData, setChartData] = useState([]);
  const [nestedTableData, setNestedTableData] = useState({
    generalTable: { columns: [], data: [] },
    paramsTable: { columns: [], data: [] },
  });
  const [nestedTablesTabVal, setNestedTablesTabVal] = useState(0);
  const [series, setSeries] = useState([]);
  const [data, setData] = useState([]);
  const [chartSummary, setChartSummary] = useState('');
  const [colors, setColors] = useState([]);
  const [timeoutValue, setTimeoutValue] = useState(1800000);
  const [downloadFormat, setDownloadFormat] = useState(1);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState({
    errorMessage: '',
    serverError: false,
    success: '',
  });

  const { linkedChartInfo, setLinkedZoomRange } = useContext(
    DashboardSettingContext
  );
  const uplotRef = useRef(null);
  const intervalRef = useRef(null);

  const theme = useTheme();
  const isLineChart =
    chartProperties?.chart?.type === CHART_TYPE.L ||
    chartProperties?.chart?.type == CHART_TYPE.CL;
  const lineChartUpdateInfo = isLineChart ? linkedChartInfo : null;

  const calculateStartEndForLineChart = (rangeSelected, min, max) => {
    if (!isLineChart) return [false, 0, 0];
    if (linkedChartInfo.linked) {
      if (linkedChartInfo.start && linkedChartInfo.end)
        return [true, linkedChartInfo.start, linkedChartInfo.end];

      let currentDateTime = new Date();
      max = currentDateTime.getTime();

      currentDateTime.setHours(
        currentDateTime.getHours() - linkedChartInfo.linked_span
      );
      min = currentDateTime.getTime();

      return [true, min, max];
    }

    // When not linked, I will still allow zooming.
    return [rangeSelected, min, max];
  };

  const fetchData = (rangeSelected = false, min = 0, max = 0) => {
    setLoading(true);
    // Calculate the start and end range based on the linked chart setting for
    // line charts.
    [rangeSelected, min, max] = calculateStartEndForLineChart(
      rangeSelected,
      min,
      max
    );

    const buildUrl = () => {
      const { data, dataWithTimespan } = chartProperties.endpoints;
      const endpoint = rangeSelected ? dataWithTimespan : data;
      const params = {
        ...chartProperties.metadata,
        ...(rangeSelected && {
          start_time: min / 1000,
          end_time: max / 1000,
        }),
      };
      return url_for(endpoint, params);
    };

    const fetchSummary = async () => {
      try {
        const { summary } = chartProperties.chart;
        if (Number(summary)) {
          const resp = await api.get(
            url_for(chartProperties.endpoints.summary, {
              ...chartProperties.metadata,
              cid: summary,
            })
          );
          setChartSummary(resp?.data?.data?.html.replace(/& #183;/g, '•'));
        }
      } catch (error) {
        handleError(error, chartProperties, setError);
      }
    };

    const handleChartData = async (data, type, title) => {
      if (
        [CHART_TYPE.P, CHART_TYPE.L, CHART_TYPE.B, CHART_TYPE.CL].includes(type)
      ) {
        const series = data?.series;
        const hasData = Boolean(data && series?.length > 0);
        const hasError = Boolean(data && !!data?.error);
        if (!hasData || hasError) {
          setError({
            errorMessage: hasError
              ? data?.error
              : CHART_CONSTANTS.NO_DATA_FOUND,
            serverError: !data || (hasError && !hasData),
            success: data?.success || false,
            hasData: hasData,
          });
          if (!hasData) return false;
        } else {
          setError({
            errorMessage: '',
            serverError: false,
            success: data?.success || true,
          });
        }

        setChartData(data);
        setSeries(handleSeries(series, type));
        setData(transformSeriesData(series, type));
        setColors(handleColors(series));
      } else if (TABLE_CHART_TYPE_VALUES.includes(type)) {
        const tableData = data?.data;
        const hasData = tableData?.length > 0;
        const hasError = !!data?.error;

        if (!hasData) {
          setError({
            errorMessage: hasError ? data.error : CHART_CONSTANTS.NO_DATA_FOUND,
            serverError: false,
            success: data?.success || false,
          });
          return false;
        }

        const filteredColumns = chartProperties?.columns?.length
          ? chartProperties.columns
            .filter(({ label }) => label.trim() !== '')
            .map(
              (col) =>
                data.columns.find(
                  (c) => c.label.toLowerCase() === col.label.toLowerCase()
                ) || col
            )
          : data.columns;

        let nodeColors = [];
        if (['Agent Status', 'Server Status'].includes(title)) {
          try {
            const nodeColorsRes = await api.get(
              url_for('charts.system_bar_settings', {
                did: 1,
                trans_id: 1732264921090,
                cid: 1,
              })
            );
            nodeColors = nodeColorsRes?.data?.data?.colors || [];
          } catch (err) {
            console.error(err);
          }
        }

        const table = {
          columns: await transformTableColumns(
            filteredColumns,
            setNestedTableData,
            type,
            () => addToQueue(fetchData, 200),
            setNestedTablesTabVal,
            setCurrentSelection,
            nodeColors
          ),
          data: tableData,
          is_nested: data?.is_nested,
          info_msg: data?.info_msg,
        };

        setChartData(table);
      }
      return true;
    };

    const request = async () => {
      try {
        const res = await api.get(buildUrl());
        await fetchSummary();

        const { chart } = chartProperties;
        const data = res?.data?.data;
        setTimeoutValue(data?.timeout ?? 1800000);
        setDownloadFormat(data?.downloadformat ?? 1);

        if (probeDisabled || res?.data?.probe_error) {
          setError({
            errorMessage: res?.data?.probe_error
              ? res?.data?.error
              : probeDisabled,
            serverError: false,
            success: data?.success || false,
            ...(res?.data?.probe_error && { probeError: true }),
          });
          return;
        }

        await handleChartData(data, chart.type, chart.title);
      } catch (error) {
        handleError(error, chartProperties, setError);
      } finally {
        setLoading(false);
      }
    };

    addToQueue(request);
  };

  const linkedChartFetchData = isLineChart
    ? (rangeSelected = false, min = 0, max = 0) => {
      if (linkedChartInfo.linked) {
        setLinkedZoomRange(min, max);
      } else {
        fetchData(rangeSelected, min, max);
      }
    }
    : fetchData;

  const opts = handleOpts(
    width,
    height,
    series,
    linkedChartFetchData,
    data,
    timeoutValue,
    intervalRef,
    chartData?.metadata?.yaxis,
    chartSummary,
    chartProperties?.chart?.type,
    uplotRef,
    theme,
    chartProperties?.metadata?.cid
  );

  useEffect(() => {
    Chart.register(sideLabelPlugin);
  }, []);

  useEffect(() => {
    addToQueue(fetchData);
  }, [lineChartUpdateInfo]);

  useEffect(() => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
    }

    intervalRef.current = setInterval(() => {
      addToQueue(fetchData);
    }, timeoutValue);
    return () => {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    };
  }, [timeoutValue]);

  const renderChart = () => {
    if (chartProperties.chart.type === CHART_TYPE.P) {
      return (
        <PieChart
          data={Array.isArray(data) && data.length === 0 ? {} : data}
          options={opts}
        />
      );
    }

    if (TABLE_CHART_TYPE_VALUES.includes(chartProperties.chart.type)) {
      return (
        <PgTable
          caveTable={false}
          columns={chartData?.columns || []}
          type='panel'
          data={chartData?.data || []}
          tableNoBorder={false}
          showSearch={true}
          variant='dashboardTable'
          NestedTable={NestedTableElement}
          customEmptyTableMessage={chartData?.info_msg}
        />
      );
    }

    return (
      <UplotReact
        target={chartContainerRef.current}
        options={opts}
        data={data}
        resetScales={true}
        onCreate={(u) => {
          uplotRef.current = u;
          if (chartProperties.chart.type === CHART_TYPE.B) {
            uplotRef.current.barSeries = series;
          }
        }}
      />
    );
  };

  const getChartDetails = () => {
    switch (chartProperties.metadata.type) {
    case 'agent':
      return `/${chartProperties.metadata.cid}/${chartProperties.metadata.aid}`;
    case 'server':
      return `/${chartProperties.metadata.cid}/${chartProperties.metadata.sid}`;
    case 'database':
      return `/${chartProperties.metadata.cid}/${chartProperties.metadata.sid}/${chartProperties.metadata.database}`;
    default:
      return `/${chartProperties.metadata.cid}`;
    }
  };

  const handleProbeEnable = () => {
    api
      .get(
        url_for('pem_dashboard.index') +
          'charts/enable_probes/' +
          chartProperties.metadata.type +
          getChartDetails()
      )
      .then(() => {
        setError({
          errorMessage: '',
          serverError: false,
          success: data.success,
        });
        addToQueue(fetchData);
      })
      .catch((errorResponse) => {
        handleError(errorResponse, chartProperties, setError);
      });
  };

  const NestedTableElement =
    chartData?.is_nested && nestedTableData ? (
      <NestedTable
        nestedTableData={nestedTableData}
        nestedTablesTabVal={nestedTablesTabVal}
        setNestedTablesTabVal={setNestedTablesTabVal}
        tabs={NESTED_TABLE_TABS[chartProperties.chart.type]}
      />
    ) : null;
  return (
    <ChartContainer
      title={chartProperties.chart.title || chartData?.metadata?.name || ''}
      refresh={() => addToQueue(fetchData, 200)}
      colors={colors}
      setColors={setColors}
      ref={{ chartContainerRef, uplotRef }}
      chartProperties={chartProperties}
      series={series}
      error={error}
      downloadFormat={downloadFormat}
    >
      {loading && <Loader message={CHART_CONSTANTS.LOADING_CHART_MESSAGE} />}
      {error.errorMessage &&
      (error?.serverError || error?.probeError || !error.hasData) ? (
          <StyledErrorDiv serverError={error?.serverError}>
            <span>
              {error?.errorMessage}
              {error?.probeError && (
                <>
                  {' '}
                  <EnableProbeLink onClick={handleProbeEnable}>
                    {CHART_CONSTANTS.CLICK_HERE}
                  </EnableProbeLink>
                  <span>{CHART_CONSTANTS.ENABLE_PROBE}</span>
                </>
              )}
            </span>
          </StyledErrorDiv>
        ) : (
          renderChart()
        )}
    </ChartContainer>
  );
};

DashboardChart.propTypes = {
  chartProperties: CustomPropTypes.chartProp,
  addToQueue: PropTypes.func.isRequired,
  setCurrentSelection: PropTypes.func.isRequired,
  probeDisabled: PropTypes.string,
};

export default DashboardChart;

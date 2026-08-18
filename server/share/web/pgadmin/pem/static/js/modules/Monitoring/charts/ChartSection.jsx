///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { memo } from 'react';
import ChartAccordion from 'pem.charts/Common/Accordian/Component';
import DashboardChart from 'pem.charts/dashboard_chart/Component';
import PropTypes from 'prop-types';
import LogViewer from 'pem/modules/log_viewer/Component';
import { getChartProperties } from 'pem.charts/Common/utils';
import {
  getTargetProperties,
  getLogViewerProperties,
} from 'pem/modules/Monitoring/Common/utils';
import {
  CHART_TYPE,
  CHART_WIDTH,
  CHART_ALIGN,
  TABLE_CHART_TYPES,
} from 'pem/common/constants';
import TextComponent from 'pem/modules/text_component/Config';

const ChartSection = memo(
  ({ dashboardData, addToQueue, setCurrentSelection }) => {
    return dashboardData?.dashboard_content?.content.map((sect, i) => {
      if (
        sect?.type === 'section' &&
        (!sect?.any || sect.any.some((key) => dashboardData.info[key] === true))
      ) {
        return (
          <ChartAccordion key={i} label={sect?.label}>
            {sect?.charts
              .sort((a, b) => a.index - b.index)
              .map((chart) => {
                if (chart.type === 'TE') {
                  return (
                    <TextComponent
                      key={`text_${chart.id}-${i}`}
                      did={dashboardData?.info?.context?.did}
                      trans_id={dashboardData?.info?.context?.trans_id}
                      cid={chart?.id}
                      aid={dashboardData?.info?.context?.aid}
                    />
                  );
                } else {
                  return (
                    <DashboardChart
                      key={`chart_${chart.id}-${i}`}
                      chartProperties={getChartProperties({
                        chart: {
                          type: CHART_TYPE[chart.type],
                          id: chart.id,
                          description:
                            chart?.description || '',
                          summary: chart?.summary || null,
                          title: chart?.label,
                        },
                        dashboard: {
                          id: dashboardData?.info?.context?.did,
                          transaction_id:
                            dashboardData?.info?.context?.trans_id,
                        },
                        target: {
                          ...getTargetProperties(dashboardData?.info?.context),
                        },
                        layout: {
                          width: CHART_WIDTH[chart?.width],
                          align: chart?.align
                            ? CHART_ALIGN[chart?.align]
                            : CHART_ALIGN[1], //1 is default for LEFT align
                        },
                        timeline: {
                          start: null,
                          end: null,
                          rangeSelected: false,
                        },
                        ...(TABLE_CHART_TYPES.includes(chart?.type) && {
                          columns: chart?.columns,
                        }),
                      })}
                      addToQueue={addToQueue}
                      setCurrentSelection={setCurrentSelection}
                      probeDisabled={
                        chart?.required
                          ? Object.entries(chart.required)
                            .filter(
                              ([key]) => dashboardData.info[key] === false
                            )
                            .map(([, message]) => message)
                            .join(' ')
                          : ''
                      }
                    />
                  );
                }
              })}
          </ChartAccordion>
        );
      } else if (sect?.type === 'infinite_table') {
        return (
          <LogViewer
            key={i}
            logViewerProperties={{
              tooltip: sect?.tooltip || '',
              label: sect?.label,
              filters: sect?.filter_on,
              ...getLogViewerProperties(
                dashboardData?.info?.context,
                sect?.url
              ),
            }}
          />
        );
      }
    });
  }
);

ChartSection.displayName = 'ChartSection';
ChartSection.propTypes = {
  dashboardData: PropTypes.object.isRequired,
  addToQueue: PropTypes.func.isRequired,
  setCurrentSelection: PropTypes.func.isRequired,
};

export default ChartSection;

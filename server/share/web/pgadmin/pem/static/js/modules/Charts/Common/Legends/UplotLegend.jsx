///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState, useEffect, forwardRef } from 'react';
import PropTypes from 'prop-types';
import CustomPropTypes from 'pem/utils/custom_prop_types';
import { StyledLegendItem } from 'pem.charts/Common/StyledComponents';
import { CHART_TYPE } from 'pem/common/constants';

const UplotLegend = forwardRef(({ series, chartType }, ref) => {
  const [visibleSeries, setVisibleSeries] = useState(() => {
    if (chartType === CHART_TYPE.P) {
      return (
        ref?.current?.chart
          ?.getDatasetMeta(0)
          ?.data?.map((i) => i?.hidden === true) || []
      );
    } else if (chartType == CHART_TYPE.L || chartType === CHART_TYPE.CL) {
      return ref?.current?.series?.map((object) => object?.show) || [];
    } else if (chartType == CHART_TYPE.B){
      return ref?.current?.barSeries?.map((object) => object.showBar) || [];
    } else return null;
  });

  const toggleSeries = (idx) => {
    const newVisibility = [...visibleSeries];
    newVisibility[idx] = !newVisibility[idx];
    setVisibleSeries(newVisibility);
    if (chartType == CHART_TYPE.P) {
      ref.current.chart.getDatasetMeta(0).data[idx].hidden = newVisibility[idx];
      ref.current.chart.update();
    } else if (chartType == CHART_TYPE.L || chartType === CHART_TYPE.CL) {
      ref.current?.setSeries(idx, { show: newVisibility[idx] });
    } else if (chartType == CHART_TYPE.B) {
      let data = [[], [], [], []];

      series.reduce((acc, object, i) => {
        if (object && newVisibility[i] && object.data?.[0]?.[1] !== undefined) {
          acc.push(object);
          data[0].push(object.label);
          data[1].push(parseInt(object.data[0][1]));
          data[2].push(object.stroke);
          data[3].push(parseInt(object.data[0][0]));
        }
        return acc;
      }, []);
      
      ref.current.barSeries = ref.current.barSeries.map((object, i) =>
        object && 'showBar' in object ? { ...object, showBar: newVisibility[i] } : {}
      );
      
      ref.current?.setData(data);
    }
  };

  useEffect(() => {
    if ((chartType == CHART_TYPE.L || chartType === CHART_TYPE.CL) && ref.current?.series) {
      setVisibleSeries(ref.current.series.map((s) => s?.show));
    }
  }, [ref.current]);

  const onClickHandler = (idx) =>
    toggleSeries(chartType === CHART_TYPE.P ? idx : idx + 1);

  return (
    <div data-testid='uplot-legend'>
      {series &&
        series.slice(1).map((obj, idx) => {
          const currentSeriesValue =
            chartType === CHART_TYPE.P
              ? visibleSeries[idx]
              : visibleSeries[idx + 1] !== undefined
                ? visibleSeries[idx + 1]
                : true;

          return (
            <StyledLegendItem
              key={idx}
              onClick={() => onClickHandler(idx)}
              stroke={obj?.stroke}
              currentSeries={currentSeriesValue}
              aria-label={obj?.label}
              chartType={chartType}
            >
              <span className='legendColor' />
              {obj?.label}
            </StyledLegendItem>
          );
        })}
    </div>
  );
});

UplotLegend.displayName = 'UplotLegend';
UplotLegend.propTypes = {
  series: CustomPropTypes.uplotSeriesProp,
  chartType: PropTypes.string,
};

export default UplotLegend;

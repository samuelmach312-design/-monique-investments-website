///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useRef } from 'react';
import PropTypes from 'prop-types';
import moment from 'moment';
import 'uplot/dist/uPlot.min.css';
import ReportHeader from './ReportHeader';
import MetricesSection from './MetricSections';
import { StyledLineChartContainer } from './StyledComponents';

const CapacityManagerReport = ({ data }) => {
  const { chart_data, report_metadata, labels } = data;
  const { report_title } = report_metadata;

  const sectionRefs = chart_data.map(() => useRef(null));

  const formattedSectionRefs = chart_data.map((item, index) => ({
    ref: sectionRefs[index],
    label: item.label,
  }));
  return (
    <StyledLineChartContainer>
      <ReportHeader
        title={report_title}
        generatedOn={moment().format('YYYY-MM-DD HH:mm:ss')}
        labels={{
          generated_on: labels.generated_on,
          go_to_text: labels.go_to_text,
        }}
        sectionRefs={formattedSectionRefs}
      />
      {chart_data.map((metric, index) => (
        <MetricesSection
          ref={sectionRefs[index]}
          data={metric}
          reportMetadata={report_metadata}
          key={index}
        />
      ))}
    </StyledLineChartContainer>
  );
};

CapacityManagerReport.propTypes = {
  data: PropTypes.object.isRequired,
};

export default CapacityManagerReport;

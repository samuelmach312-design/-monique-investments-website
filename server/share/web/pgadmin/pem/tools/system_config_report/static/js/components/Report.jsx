///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useRef } from 'react';
import PropTypes from 'prop-types';
import Summary from './Summary';
import PemSummary from './PemSummary';
import ReportHeader from './ReportHeader';
import MonitoringOverview from './MonitoringOverview';
import { StyledContainer } from './StyledComponents';
import { TableSizesSection } from './TableSizesSection';

import GroupSection from './GroupSection';
import SizingInfoSection from './SizingInfo';
import AgentInfoSection from './AgentInfoSection';

const Report = ({ data }) => {
  const {
    pem_info,
    report,
    report_header_labels,
    pem_summary_labels,
    summary_labels,
    summary,
    pem_agents_labels,
    pem_servers_labels,
    pem_table_sizes,
    pem_table_sizes_columns,
    common_labels,
    monitoring_overview,
    sizing_info,
    agent_info
  } = data;

  // Refs for each section
  const pemSummaryRef = useRef(null);
  const summaryRef = useRef(null);
  const monitoringRef = useRef(null);
  const sizingRef = useRef(null);
  const agentInfoRef = useRef(null);
  const sectionRefs = Object.keys(report).map(() => useRef(null));
  const tableSizesRef = useRef(null);

  // Build refs with labels
  const formattedSectionRefs = [
    { ref: pemSummaryRef, label: pem_summary_labels.header },
    { ref: summaryRef, label: summary_labels.header },
    { ref: monitoringRef, label: monitoring_overview.header },
    { ref: agentInfoRef, label: agent_info.header },
    ...Object.values(report).map((item, index) => ({
      ref: sectionRefs[index],
      label: item.name,
    })),
    { ref: sizingRef, label: sizing_info.header },
  ];

  return (
    <StyledContainer>
      <ReportHeader
        generatedOn={new Date().toLocaleString()}
        sectionRefs={formattedSectionRefs}
        labels={report_header_labels}
      />

      <div ref={pemSummaryRef}>
        <PemSummary data={pem_info} labels={pem_summary_labels} />
      </div>

      <div ref={summaryRef}>
        <Summary summaryData={summary} labels={summary_labels} />
      </div>

      <div ref={monitoringRef}>
        <MonitoringOverview data={monitoring_overview} />
      </div>

      <div ref={agentInfoRef}>
        <AgentInfoSection agentInfo={agent_info} />
      </div>

      {Object.values(report).map((_report, index) => (
        <div key={index} ref={sectionRefs[index]}>
          <GroupSection
            key={index}
            groupData={_report}
            labels={{
              pem_agents_labels: pem_agents_labels,
              pem_servers_labels: pem_servers_labels,
              common_labels: common_labels,
            }}
          />
        </div>
      ))}

      {pem_table_sizes && (
        <div ref={tableSizesRef}>
          <TableSizesSection
            groupData={pem_table_sizes}
            labels={report_header_labels}
            columns={pem_table_sizes_columns}
          />
        </div>
      )}

      <div ref={sizingRef}>
        <SizingInfoSection sizingInfo={sizing_info} />
      </div>
    </StyledContainer>
  );
};

Report.propTypes = {
  data: PropTypes.shape({
    pem_info: PropTypes.object.isRequired,
    report: PropTypes.objectOf(
      PropTypes.shape({
        name: PropTypes.string.isRequired,
        agents: PropTypes.arrayOf(PropTypes.object),
        servers: PropTypes.arrayOf(
          PropTypes.shape({
            id: PropTypes.number.isRequired,
            description: PropTypes.string.isRequired,
            host: PropTypes.string.isRequired,
            port: PropTypes.number.isRequired,
            version: PropTypes.string,
            agent_name: PropTypes.string,
            database: PropTypes.string.isRequired,
            active: PropTypes.bool.isRequired,
            is_remote_monitoring: PropTypes.bool.isRequired,
            service_id: PropTypes.oneOfType([
              PropTypes.string,
              PropTypes.number,
            ]),
            db_details: PropTypes.arrayOf(
              PropTypes.shape({
                database_name: PropTypes.string.isRequired,
                database_size_mb: PropTypes.string.isRequired,
                tablespace_name: PropTypes.string.isRequired,
              })
            ),
            tablespace_details: PropTypes.arrayOf(
              PropTypes.shape({
                tablespace_name: PropTypes.string.isRequired,
                tablespace_size_mb: PropTypes.string.isRequired,
              })
            ),
          })
        ),
      })
    ).isRequired,
    report_header_labels: PropTypes.shape({
      header: PropTypes.string.isRequired,
      go_to_text: PropTypes.string.isRequired,
      table_sizes: PropTypes.string.isRequired,
    }).isRequired,
    pem_summary_labels: PropTypes.shape({
      header: PropTypes.string.isRequired,
      columns: PropTypes.arrayOf(
        PropTypes.shape({
          header: PropTypes.string.isRequired,
          accessor: PropTypes.string.isRequired,
        })
      ).isRequired,
    }).isRequired,
    summary_labels: PropTypes.shape({
      header: PropTypes.string.isRequired,
      columns: PropTypes.arrayOf(
        PropTypes.shape({
          header: PropTypes.string.isRequired,
          accessor: PropTypes.string.isRequired,
        })
      ).isRequired,
    }).isRequired,
    common_labels: PropTypes.object.isRequired,
    summary: PropTypes.object.isRequired,
    pem_agents_labels: PropTypes.object.isRequired,
    pem_servers_labels: PropTypes.object.isRequired,
    pem_table_sizes: PropTypes.array,
    pem_table_sizes_columns: PropTypes.array,
    monitoring_overview: PropTypes.object,
    sizing_info: PropTypes.object,
    agent_info: PropTypes.object,
  }).isRequired,
};

export default Report;

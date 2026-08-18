///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import { Box, Typography } from '@mui/material';
import { styled } from '@mui/material/styles';
import { MinimalisticPgTable } from './MinimalisticPgTable';
import ReportHeader from './ReportHeader';

const StyledContainer = styled(Box)(({ theme }) => ({
  padding: theme.spacing(2),
  backgroundColor: theme.palette.default.hoverMain,
}));

const StyledSection = styled(Box)(({ theme }) => ({
  marginTop: theme.spacing(4),
}));

const StyledCard = styled(Box)(({ theme }) => ({
  border: `1px solid ${theme.palette.divider}`,
  borderRadius: theme.shape.borderRadius,
  backgroundColor: theme.otherVars.report.cardBg,
  marginBottom: theme.spacing(2),
}));

const StyledCardHeader = styled(Box)(({ theme }) => ({
  borderBottom: `1px solid ${theme.palette.divider}`,
  backgroundColor: theme.palette.common.white,
  padding: theme.spacing(1),
}));

const StyledCardBody = styled(Box)(({ theme }) => ({
  padding: theme.spacing(2),
}));

const StyledTableContainer = styled(Box)(({ theme }) => ({
  marginTop: theme.spacing(2),
}));

const StyledSectionBox = styled(Box)(({ theme }) => ({
  marginBottom: theme.spacing(3), // Adds consistent bottom margin (24px by default)
}));

const renderTable = (title, columns, rows, key) => (
  <StyledTableContainer key={key}>
    <MinimalisticPgTable columns={columns} data={rows} />
  </StyledTableContainer>
);

const Report = ({ data }) => {
  const {
    pem_info,
    report,
    report_header_labels,
    core_summary_labels,
    server_summary_labels,
  } = data;

  const {
    total_cpu_cores,
    servers,
    total_locally_managed_servers,
    total_remotely_managed_servers,
    total_unmanaged_servers,
  } = report;

  const serverSummaryColumns = server_summary_labels.server_summary_columns;

  const serverSummaryData = (() => {
    const summaryData = servers
      .filter((server) => !server.is_remote_monitoring && server.agent_name)
      .map((server) => ({
        name: server.name || 'N/A',
        type: server.server_type || 'N/A',
        hostPort:
          server.host && server.port ? `${server.host}:${server.port}` : 'N/A',
        pgd: server.is_pgd === 'True' ? 'Yes' : 'No',
        pgdVersion: server.pgd_extension_version || 'N/A',
        platform: server.platform || 'N/A',
        cores: server.cpu_cores ?? 'N/A',
        ram: server.total_ram_memory_mb ?? 'N/A',
      }));

    const totalCores = servers.reduce(
      (sum, server) => sum + server.cpu_cores,
      0
    );
    const totalRam = servers.reduce(
      (sum, server) => sum + server.total_ram_memory_mb,
      0
    );

    summaryData.push({
      name: '',
      type: '',
      hostPort: '',
      pgd: '',
      pgdVersion: '',
      platform: '',
      cores: totalCores,
      ram: totalRam,
    });

    return summaryData;
  })();

  const remoteServerColumns = server_summary_labels.remote_servers_columns;
  const remoteServerData = servers
    .filter((server) => server.is_remote_monitoring && server.agent_name)
    .map((server) => ({
      name: server.name || 'N/A',
      type: server.server_type || 'N/A',
      hostPort:
        server.host && server.port ? `${server.host}:${server.port}` : 'N/A',
      pgd: server.is_pgd === 'True' ? 'Yes' : 'No',
      pgdVersion: server.pgd_extension_version || 'N/A',
      platform: server.platform || 'N/A',
      cores: server.cpu_cores ?? 'N/A', // Use nullish coalescing to handle 0 or null
      ram: server.total_ram_memory_mb ?? 'N/A',
    }));

  const unmanagedServerColumns =
    server_summary_labels.unmanaged_servers_columns;
  const unmanagedServerData = servers
    .filter((server) => !server.is_remote_monitoring && !server.agent_name)
    .map((server) => ({
      name: server.name || 'N/A',
      type: server.server_type || 'N/A',
      hostPort:
        server.host && server.port ? `${server.host}:${server.port}` : 'N/A',
      pgd: server.is_pgd === 'True' ? 'Yes' : 'No',
      pgdVersion: server.pgd_extension_version || 'N/A',
      platform: server.platform || 'N/A',
      cores: server.cpu_cores ?? 'N/A', // Use nullish coalescing to handle 0 or null
      ram: server.total_ram_memory_mb ?? 'N/A',
    }));

  const coreSummaryTables = [
    {
      columns: core_summary_labels.server_type_columns,
      dataExtractor: (data) => {
        const serverTypeData = data.count_by_server_type.map((item) => ({
          type: item.type,
          servers: item.count,
          cores: item.cpu_cores,
        }));
        
        return serverTypeData;
      },
    },
    {
      columns: core_summary_labels.database_version_columns,
      dataExtractor: (data) =>
        data.count_by_server_version.map((item) => ({
          version: item.version,
          servers: item.servers,
          cores: item.core_count,
        })),
    },
    {
      columns: core_summary_labels.platform_columns,
      dataExtractor: (data) =>
        data.count_by_platform.map((item) => ({
          platform: item.platform,
          servers: item.servers,
          cores: item.cpu_cores,
        })),
    },
    {
      columns: core_summary_labels.group_name_columns,
      dataExtractor: (data) =>
        data.count_by_group.map((item) => ({
          name: item.name,
          servers: item.servers,
          cores: item.cpu_cores,
        })),
    },
  ];

  return (
    <StyledContainer>
      <ReportHeader
        title={report_header_labels.header}
        generatedOn={new Date().toLocaleString()}
        pemInfo={{
          name: pem_info.name,
          version: pem_info.version,
          schema: pem_info.schema,
        }}
        labels={report_header_labels}
      />
      <StyledSection>
        <StyledCard>
          <StyledCardHeader>
            <Typography variant="h5" gutterBottom>
              {core_summary_labels.core_summary}
            </Typography>
          </StyledCardHeader>
          <StyledCardBody>
            <Typography variant="body1" gutterBottom>
              <strong>{core_summary_labels.total_number_of_cores}:</strong>{' '}
              {total_cpu_cores}
            </Typography>
            {coreSummaryTables.map((table, index) =>
              renderTable(
                table.title,
                table.columns,
                table.dataExtractor(report),
                index
              )
            )}
          </StyledCardBody>
        </StyledCard>
      </StyledSection>

      <StyledSection>
        <StyledCard>
          <StyledCardHeader>
            <Typography variant="h5" gutterBottom>
              {server_summary_labels.server_summary}
            </Typography>
          </StyledCardHeader>
          <StyledCardBody>
            {total_locally_managed_servers !== null && (
              <StyledSectionBox>
                <Typography variant="body1" gutterBottom>
                  <strong>
                    {server_summary_labels.locally_managed_servers}:
                  </strong>{' '}
                  {total_locally_managed_servers}
                </Typography>
                <StyledTableContainer>
                  <MinimalisticPgTable
                    columns={serverSummaryColumns}
                    data={serverSummaryData}
                    showFooter={true}
                  />
                </StyledTableContainer>
              </StyledSectionBox>
            )}
            {total_remotely_managed_servers !== null && (
              <StyledSectionBox>
                <Typography variant="body1" gutterBottom>
                  <strong>{server_summary_labels.remote_servers}:</strong>{' '}
                  {total_remotely_managed_servers}
                </Typography>
                <StyledTableContainer>
                  <MinimalisticPgTable
                    columns={remoteServerColumns}
                    data={remoteServerData}
                  />
                </StyledTableContainer>
              </StyledSectionBox>
            )}

            {total_unmanaged_servers !== null && (
              <StyledSectionBox>
                <Typography variant="body1" gutterBottom>
                  <strong>{server_summary_labels.unmanaged_servers}:</strong>{' '}
                  {total_unmanaged_servers}
                </Typography>
                <StyledTableContainer>
                  <MinimalisticPgTable
                    columns={unmanagedServerColumns}
                    data={unmanagedServerData}
                  />
                </StyledTableContainer>
              </StyledSectionBox>
            )}
          </StyledCardBody>
        </StyledCard>
      </StyledSection>
    </StyledContainer>
  );
};

Report.propTypes = {
  data: PropTypes.shape({
    pem_info: PropTypes.shape({
      name: PropTypes.string.isRequired,
      version: PropTypes.string.isRequired,
      schema: PropTypes.oneOfType([PropTypes.string, PropTypes.number])
        .isRequired,
    }).isRequired,

    report: PropTypes.shape({
      total_cpu_cores: PropTypes.number.isRequired,
      servers: PropTypes.arrayOf(
        PropTypes.shape({
          name: PropTypes.string.isRequired,
          server_type: PropTypes.string.isRequired,
          host: PropTypes.string.isRequired,
          port: PropTypes.number.isRequired,
          is_pgd: PropTypes.string.isRequired,
          pgd_extension_version: PropTypes.string,
          platform: PropTypes.string.isRequired,
          cpu_cores: PropTypes.number.isRequired,
          total_ram_memory_mb: PropTypes.number.isRequired,
        })
      ).isRequired,
      total_locally_managed_servers: PropTypes.number,
      total_remotely_managed_servers: PropTypes.number,
      total_unmanaged_servers: PropTypes.number,
    }).isRequired,

    count_by_server_type: PropTypes.arrayOf(
      PropTypes.shape({
        type: PropTypes.string.isRequired,
        count: PropTypes.number.isRequired,
        cpu_cores: PropTypes.number.isRequired,
      })
    ).isRequired,

    count_by_server_version: PropTypes.arrayOf(
      PropTypes.shape({
        version: PropTypes.string.isRequired,
        servers: PropTypes.number.isRequired,
        core_count: PropTypes.number.isRequired,
      })
    ).isRequired,

    count_by_platform: PropTypes.arrayOf(
      PropTypes.shape({
        platform: PropTypes.string.isRequired,
        servers: PropTypes.number.isRequired,
        cpu_cores: PropTypes.number.isRequired,
      })
    ).isRequired,

    count_by_group: PropTypes.arrayOf(
      PropTypes.shape({
        name: PropTypes.string.isRequired,
        servers: PropTypes.number.isRequired,
        cpu_cores: PropTypes.number.isRequired,
      })
    ).isRequired,

    report_header_labels: PropTypes.shape({
      header: PropTypes.string.isRequired,
      generated_on: PropTypes.string.isRequired,
      go_to_text: PropTypes.string.isRequired,
      pem_agents: PropTypes.string.isRequired,
      pem_server_dir: PropTypes.string.isRequired,
    }).isRequired,

    core_summary_labels: PropTypes.shape({
      core_summary: PropTypes.string.isRequired,
      total_number_of_cores: PropTypes.string.isRequired,
      server_type_columns: PropTypes.arrayOf(
        PropTypes.shape({
          header: PropTypes.string.isRequired,
          accessor: PropTypes.string.isRequired,
        })
      ).isRequired,
      database_version_columns: PropTypes.arrayOf(
        PropTypes.shape({
          header: PropTypes.string.isRequired,
          accessor: PropTypes.string.isRequired,
        })
      ).isRequired,
      platform_columns: PropTypes.arrayOf(
        PropTypes.shape({
          header: PropTypes.string.isRequired,
          accessor: PropTypes.string.isRequired,
        })
      ).isRequired,
      group_name_columns: PropTypes.arrayOf(
        PropTypes.shape({
          header: PropTypes.string.isRequired,
          accessor: PropTypes.string.isRequired,
        })
      ).isRequired,
    }).isRequired,

    server_summary_labels: PropTypes.shape({
      server_summary: PropTypes.string.isRequired,
      locally_managed_servers: PropTypes.string.isRequired,
      remotely_managed_servers: PropTypes.string.isRequired,
      unmanaged_servers: PropTypes.string.isRequired,
      remote_servers: PropTypes.string.isRequired,
      server_summary_columns: PropTypes.arrayOf(
        PropTypes.shape({
          header: PropTypes.string.isRequired,
          accessor: PropTypes.string.isRequired,
        })
      ).isRequired,
      remote_servers_columns: PropTypes.arrayOf(
        PropTypes.shape({
          header: PropTypes.string.isRequired,
          accessor: PropTypes.string.isRequired,
        })
      ),
      unmanaged_servers_columns: PropTypes.arrayOf(
        PropTypes.shape({
          header: PropTypes.string.isRequired,
          accessor: PropTypes.string.isRequired,
        })
      ).isRequired,
    }).isRequired,
  }).isRequired,
};

export default Report;

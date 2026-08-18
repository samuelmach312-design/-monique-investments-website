///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import AccordionSummary from '@mui/material/AccordionSummary';
import Typography from '@mui/material/Typography';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import {
  StyledAccordion,
  StyledAccordionDetails,
  TableContainer,
  StyledHeaderBox,
  StyledTypography,
} from './StyledComponents';
import { AccordianWithTable } from './AccordianWithTable';

const GroupSection = ({ groupData, labels }) => {
  const { pem_agents_labels, pem_servers_labels, common_labels } = labels;

  return (
    <StyledAccordion defaultExpanded>
      <AccordionSummary expandIcon={<ExpandMoreIcon />}>
        <Typography variant="h6">
          {common_labels.group_name}: {groupData.name}
        </Typography>
      </AccordionSummary>
      <StyledAccordionDetails>
        {groupData.agents.map((agent) => (
          <TableContainer key={agent.id}>
            {/* Agent Header */}
            <StyledHeaderBox>
              <StyledTypography variant="h6">
                {pem_agents_labels.agent.agent_description}: {agent.description}
              </StyledTypography>
            </StyledHeaderBox>
            <AccordianWithTable
              section_header={pem_agents_labels.agent.agent_details}
              table_data={[
                {
                  parameter: pem_agents_labels.agent.platform,
                  value: agent.platform,
                },
                {
                  parameter: pem_agents_labels.agent.os,
                  value: agent.os_details,
                },
                {
                  parameter: pem_agents_labels.agent.version,
                  value: agent.version,
                },
                {
                  parameter: pem_agents_labels.agent.active,
                  value: agent.active ? 'True' : 'False',
                },
                {
                  parameter: pem_agents_labels.agent.hostname,
                  value: agent.hostname,
                },
                {
                  parameter: pem_agents_labels.agent.domain_name,
                  value: agent.domainname,
                },
                {
                  parameter: pem_agents_labels.agent.bound_local_servers,
                  value:
                    agent.bound_local_servers &&
                    agent.bound_local_servers.length > 0
                      ? agent.bound_local_servers
                        .map((server) => server.server_name)
                        .join(', ')
                      : pem_agents_labels.agent.none,
                },
                {
                  parameter: pem_agents_labels.agent.bound_remote_servers,
                  value:
                    agent.bound_remote_servers &&
                    agent.bound_remote_servers.length > 0
                      ? agent.bound_remote_servers
                        .map((server) => server.server_name)
                        .join(', ')
                      : pem_agents_labels.agent.none,
                },
              ]}
              columns={[
                {
                  header: pem_agents_labels.agent.parameter,
                  accessor: 'parameter',
                },
                {
                  header: pem_agents_labels.agent.value,
                  accessor: 'value',
                },
              ]}
            />

            <AccordianWithTable
              section_header={pem_agents_labels.cpu.section_title}
              table_data={agent.cpu_core_details}
              columns={[
                {
                  header: pem_agents_labels.cpu.core_id,
                  accessor: 'core_id',
                },
                {
                  header: pem_agents_labels.cpu.load_percentage,
                  accessor: 'load_percentage',
                },
              ]}
              summary={[
                {
                  label: pem_agents_labels.cpu.total_cores,
                  data: agent.total_cpu_cores,
                },
                {
                  label: pem_agents_labels.cpu.avg_utilization,
                  data: agent.avg_cpu_utilization_percentage,
                },
              ]}
            />
            <AccordianWithTable
              section_header={pem_agents_labels.disk.section_title}
              columns={[
                {
                  header: pem_agents_labels.disk.mount_point,
                  accessor: 'mount_point',
                },
                {
                  header: pem_agents_labels.disk.file_system,
                  accessor: 'file_system',
                },
                {
                  header: pem_agents_labels.disk.size_mb,
                  accessor: 'size_mb',
                },
                {
                  header: pem_agents_labels.disk.space_used_mb,
                  accessor: 'space_used_mb',
                },
                {
                  header: pem_agents_labels.disk.space_available_mb,
                  accessor: 'space_available_mb',
                },
              ]}
              table_data={agent.disk_utilization_details}
              summary={[
                {
                  label: pem_agents_labels.disk.total_disk_size,
                  data: agent.total_disk_size_mb,
                },
                {
                  label: pem_agents_labels.disk.disk_space_used,
                  data: agent.total_disk_space_used_mb,
                },
                {
                  label: pem_agents_labels.disk.disk_space_available,
                  data: agent.total_disk_space_available_mb,
                },
                {
                  label: pem_agents_labels.disk.disk_utilization,
                  data: agent.disk_utilization_percentage,
                },
              ]}
            />
            <AccordianWithTable
              section_header={pem_agents_labels.memory.section_title}
              columns={[
                {
                  header: pem_agents_labels.memory.parameter,
                  accessor: 'parameter',
                },
                {
                  header: pem_agents_labels.memory.value,
                  accessor: 'value',
                },
              ]}
              table_data={[
                {
                  parameter: pem_agents_labels.memory.total_ram,
                  value: agent.mem_details.total_ram_memory_mb,
                },
                {
                  parameter: pem_agents_labels.memory.free_ram,
                  value: agent.mem_details.free_ram_memory_mb,
                },
                {
                  parameter: pem_agents_labels.memory.memory_usage,
                  value: agent.mem_details.mem_usage_percentage,
                },
                {
                  parameter: pem_agents_labels.memory.total_swap,
                  value: agent.mem_details.total_swap_memory_mb,
                },
                {
                  parameter: pem_agents_labels.memory.free_swap,
                  value: agent.mem_details.free_swap_memory_mb,
                },
                {
                  parameter: pem_agents_labels.memory.swap_usage,
                  value: agent.mem_details.swap_usage_percentage,
                },
              ]}
            />
          </TableContainer>
        ))}
        {groupData.servers.map((server) => {
          return (
            <TableContainer key={server.id}>
              <StyledHeaderBox>
                <StyledTypography variant="subtitle1">
                  {pem_servers_labels.server.header}: {server.description}
                </StyledTypography>
              </StyledHeaderBox>
              <AccordianWithTable
                section_header={pem_servers_labels.server.details}
                columns={[
                  {
                    header: pem_servers_labels.server.parameter,
                    accessor: 'parameter',
                  },
                  {
                    header: pem_servers_labels.server.value,
                    accessor: 'value',
                  },
                ]}
                table_data={[
                  {
                    parameter: pem_servers_labels.server.agent,
                    value: server.agent_name || pem_servers_labels.server.none,
                  },
                  {
                    parameter: pem_servers_labels.server.host,
                    value: server.host,
                  },
                  {
                    parameter: pem_servers_labels.server.port,
                    value: server.port,
                  },
                  {
                    parameter: pem_servers_labels.server.database,
                    value: server.database,
                  },
                  {
                    parameter: pem_servers_labels.server.version,
                    value: server.version || pem_servers_labels.server.none,
                  },
                  {
                    parameter: pem_servers_labels.server.service_id,
                    value: server.service_id || pem_servers_labels.server.none,
                  },
                  {
                    parameter: pem_servers_labels.server.remote_monitored,
                    value: server.is_remote_monitoring ? 'Yes' : 'No',
                  },
                  {
                    parameter: pem_servers_labels.server.active,
                    value: server.active ? 'True' : 'False',
                  },
                ]}
              />

              <AccordianWithTable
                section_header={pem_servers_labels.database.header}
                columns={[
                  {
                    header: pem_servers_labels.database.name,
                    accessor: 'database_name',
                  },
                  {
                    header: pem_servers_labels.database.size_mb,
                    accessor: 'database_size_mb',
                  },
                  {
                    header: pem_servers_labels.database.tablespace_name,
                    accessor: 'tablespace_name',
                  },
                ]}
                table_data={server.db_details}
              />

              <AccordianWithTable
                section_header={pem_servers_labels.tablespace.header}
                columns={[
                  {
                    header: pem_servers_labels.tablespace.name,
                    accessor: 'tablespace_name',
                  },
                  {
                    header: pem_servers_labels.tablespace.size_mb,
                    accessor: 'tablespace_size_mb',
                  },
                ]}
                table_data={server.tablespace_details}
              />
              <AccordianWithTable
                section_header={pem_servers_labels.object_count.header}
                columns={[
                  {
                    header: pem_servers_labels.object_count.name,
                    accessor: 'name',
                  },
                  {
                    header: pem_servers_labels.object_count.count,
                    accessor: 'count',
                  },
                ]}
                table_data={Object.entries(server.object_count).map(
                  ([key, value]) => ({
                    name: key
                      .replace(/_/g, ' ')
                      .replace(/\b\w/g, (char) => char.toUpperCase()),
                    count: value,
                  })
                )}
              />
              <AccordianWithTable
                section_header={
                  pem_servers_labels.db_objects_stats.section_title
                }
                columns={[
                  {
                    header: pem_servers_labels.db_objects_stats.db_hash,
                    accessor: 'db_hash',
                  },
                  {
                    header: pem_servers_labels.db_objects_stats.schema_hash,
                    accessor: 'schema_hash',
                  },
                  {
                    header: pem_servers_labels.db_objects_stats.tables,
                    accessor: 'tables',
                  },
                  {
                    header: pem_servers_labels.db_objects_stats.indexes,
                    accessor: 'indexes',
                  },
                ]}
                table_data={server.db_objects_stats}
              />
            </TableContainer>
          );
        })}
      </StyledAccordionDetails>
    </StyledAccordion>
  );
};

GroupSection.propTypes = {
  groupData: PropTypes.object.isRequired,
  labels: PropTypes.object.isRequired,
};

export default GroupSection;

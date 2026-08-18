///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import Accordion from '@mui/material/Accordion';
import AccordionSummary from '@mui/material/AccordionSummary';
import AccordionDetails from '@mui/material/AccordionDetails';
import Typography from '@mui/material/Typography';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import { MinimalisticPgTable } from './MinimalisticPgTable';

const Summary = ({ summaryData, labels }) => {
  const summaryRows = [
    {
      parameter: labels.key_map.agents,
      value: {
        Windows: summaryData.total_windows_agents,
        Linux: summaryData.total_unix_linux_agents,
      },
    },
    {
      parameter: labels.key_map.servers,
      value: {
        PG: summaryData.total_pg_servers,
        EPAS: summaryData.total_epas_servers,
        [labels.key_map.unknown]: summaryData.total_unknwon_servers,
        [labels.key_map.locally_managed]:
          summaryData.total_locally_monitored_servers,
        [labels.key_map.remotely_managed]:
          summaryData.total_remotely_monitored_servers,
        [labels.key_map.unmanaged]: summaryData.total_unmanaged_servers,
      },
    },
  ];
  return (
    <Accordion defaultExpanded>
      <AccordionSummary expandIcon={<ExpandMoreIcon />}>
        <Typography variant="h6">{labels.header}</Typography>
      </AccordionSummary>
      <AccordionDetails>
        <MinimalisticPgTable columns={labels.columns} data={summaryRows} />
      </AccordionDetails>
    </Accordion>
  );
};

Summary.propTypes = {
  summaryData: PropTypes.shape({
    total_windows_agents: PropTypes.number.isRequired,
    total_unix_linux_agents: PropTypes.number.isRequired,
    total_pg_servers: PropTypes.number.isRequired,
    total_epas_servers: PropTypes.number.isRequired,
    total_unknwon_servers: PropTypes.number.isRequired,
    total_locally_monitored_servers: PropTypes.number.isRequired,
    total_remotely_monitored_servers: PropTypes.number.isRequired,
    total_unmanaged_servers: PropTypes.number.isRequired,
  }).isRequired,
  labels: PropTypes.shape({
    header: PropTypes.string.isRequired,
    columns: PropTypes.arrayOf(
      PropTypes.shape({
        header: PropTypes.string.isRequired,
        accessor: PropTypes.string.isRequired,
      })
    ).isRequired,
    key_map: PropTypes.shape({
      agents: PropTypes.string.isRequired,
      servers: PropTypes.string.isRequired,
      unknown: PropTypes.string.isRequired,
      locally_managed: PropTypes.string.isRequired,
      remotely_managed: PropTypes.string.isRequired,
      unmanaged: PropTypes.string.isRequired,
    }).isRequired,
  }).isRequired,
};

export default Summary;

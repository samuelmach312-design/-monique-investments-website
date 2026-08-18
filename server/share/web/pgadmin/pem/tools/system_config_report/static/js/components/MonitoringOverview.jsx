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


const MonitoringOverview = ({ data }) => {
  const rows = Object.entries(data.data).map(([key, value]) => ({
    parameter: data.label_keymap[key] || key,
    value: value,
  }));

  return (
    <Accordion defaultExpanded>
      <AccordionSummary expandIcon={<ExpandMoreIcon />}>
        <Typography variant="h6">{data.header}</Typography>
      </AccordionSummary>
      <AccordionDetails>
        <MinimalisticPgTable columns={data.columns} data={rows} />
      </AccordionDetails>
    </Accordion>
  );
};

MonitoringOverview.propTypes = {
  data: PropTypes.object.isRequired,
};

export default MonitoringOverview;

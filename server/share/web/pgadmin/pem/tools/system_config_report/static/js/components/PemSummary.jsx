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

const PemSummary = ({ data, labels }) => {
  const transformedData = Object.entries(data).map(([key, value]) => ({
    parameter: key.charAt(0).toUpperCase() + key.slice(1),
    value,
  }));
  return (
    <Accordion defaultExpanded>
      <AccordionSummary expandIcon={<ExpandMoreIcon />}>
        <Typography variant="h6">{labels.header}</Typography>
      </AccordionSummary>
      <AccordionDetails>
        <MinimalisticPgTable
          columns={labels.columns}
          data={transformedData}
          nestedKey="value"
        />
      </AccordionDetails>
    </Accordion>
  );
};

PemSummary.propTypes = {
  data: PropTypes.object.isRequired,
  labels: PropTypes.shape({
    header: PropTypes.string.isRequired,
    columns: PropTypes.arrayOf(
      PropTypes.shape({
        header: PropTypes.string.isRequired,
        accessor: PropTypes.string.isRequired,
      })
    ).isRequired,
  }).isRequired,
};

export default PemSummary;

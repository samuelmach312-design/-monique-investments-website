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
import { MinimalisticPgTable } from './MinimalisticPgTable';
import { StyledAccordion, StyledAccordionDetails } from './StyledComponents';

export const TableSizesSection = ({ groupData, labels, columns }) => {
  return (
    <StyledAccordion defaultExpanded>
      <AccordionSummary expandIcon={<ExpandMoreIcon />}>
        <Typography variant="h6">{labels.table_sizes}</Typography>
      </AccordionSummary>
      <StyledAccordionDetails>
        <MinimalisticPgTable columns={columns} data={groupData} />
      </StyledAccordionDetails>
    </StyledAccordion>
  );
};

TableSizesSection.propTypes = {
  groupData: PropTypes.array,
  labels: PropTypes.object,
  columns: PropTypes.array,
};

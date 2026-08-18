///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import Typography from '@mui/material/Typography';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import { MinimalisticPgTable } from './MinimalisticPgTable';
import {
  StyledAccordion,
  StyledAccordionSummary,
  StyledAccordionDetails,
  SmallInfoIcon,
  SummaryHeader,
} from './StyledComponents';

export const AccordianWithTable = ({
  section_header,
  columns,
  table_data,
  summary,
}) => {
  return (
    <StyledAccordion>
      <StyledAccordionSummary expandIcon={<ExpandMoreIcon />}>
        <Typography>{section_header}</Typography>
      </StyledAccordionSummary>
      <StyledAccordionDetails>
        {table_data && table_data.length > 0 ? (
          <>
            {summary &&
              summary.map(({ label, data }, index) => (
                <SummaryHeader key={index}>
                  {label}: {data}
                </SummaryHeader>
              ))}
            <MinimalisticPgTable columns={columns} data={table_data} />
          </>
        ) : (
          <div style={{ textAlign: 'center' }}>
            <span>
              <SmallInfoIcon /> No data found.
            </span>
          </div>
        )}
      </StyledAccordionDetails>
    </StyledAccordion>
  );
};

AccordianWithTable.propTypes = {
  section_header: PropTypes.string.isRequired,
  columns: PropTypes.array.isRequired,
  summary: PropTypes.array,
  table_data: PropTypes.array,
};

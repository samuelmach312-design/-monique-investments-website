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
  SummaryHeader,
  TableContainer,
} from './StyledComponents';
import { AccordianWithTable } from './AccordianWithTable';

const AgentInfoSection = ({ agentInfo }) => {
  const { header, data, summary } = agentInfo;

  return (
    <StyledAccordion defaultExpanded>
      <AccordionSummary expandIcon={<ExpandMoreIcon />}>
        <Typography variant="h6">{header}</Typography>
      </AccordionSummary>
      <StyledAccordionDetails>
        {summary &&
          summary.map(({ label, data }, index) => (
            <SummaryHeader key={index}>
              {label}: {data}
            </SummaryHeader>
          ))}
        {Object.keys(data).map((key) => {
          const currentObj = data[key];
          return (
            <TableContainer key={currentObj.header}>
              <AccordianWithTable
                section_header={currentObj.header}
                table_data={currentObj.data}
                columns={currentObj.columns}
              />
            </TableContainer>
          );
        })}
      </StyledAccordionDetails>
    </StyledAccordion>
  );
};

AgentInfoSection.propTypes = {
  agentInfo: PropTypes.object.isRequired,
};

export default AgentInfoSection;

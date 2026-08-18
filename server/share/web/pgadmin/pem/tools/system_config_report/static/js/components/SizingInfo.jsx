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
} from './StyledComponents';
import { AccordianWithTable } from './AccordianWithTable';

const SizingInfoSection = ({ sizingInfo }) => {
  const { header, data } = sizingInfo;

  return (
    <StyledAccordion defaultExpanded>
      <AccordionSummary expandIcon={<ExpandMoreIcon />}>
        <Typography variant="h6">{header}</Typography>
      </AccordionSummary>
      <StyledAccordionDetails>
        {data.map((currentObj) => {
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

SizingInfoSection.propTypes = {
  sizingInfo: PropTypes.object.isRequired,
};

export default SizingInfoSection;

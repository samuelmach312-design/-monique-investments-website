///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState } from 'react';
import PropTypes from 'prop-types';
import AccordionSummary from '@mui/material/AccordionSummary';
import Grid from '@mui/material/Grid';
import gettext from 'sources/gettext';
import CustomPropTypes from 'pem/utils/custom_prop_types';
import {
  StyledAccordian,
  StyledAccordianDetails,
  RotatingExpandMoreIcon,
} from 'pem.charts/Common/StyledComponents';
import { generateRandomNumber } from 'pem/common/utils';
import {
  StyledAccordionHeader,
  StyledAccordionWrapper,
} from 'pem/common/StyledComponents';

const ChartAccordion = (props) => {
  const [expanded, setExpanded] = useState(true);
  return (
    <StyledAccordionWrapper>
      <StyledAccordian
        expanded={expanded}
        onChange={() => setExpanded((prevExpanded) => !prevExpanded)}
        disableGutters
      >
        <AccordionSummary
          expandIcon={
            <RotatingExpandMoreIcon
              ownerState={{ expanded }}
              fontSize='small'
            />
          }
          aria-controls='panel1a-content'
          aria-label={gettext(props?.label)}
          id={`panel1a-header${generateRandomNumber()}`}
        >
          <StyledAccordionHeader>{gettext(props?.label)}</StyledAccordionHeader>
        </AccordionSummary>
        <StyledAccordianDetails ownerState={{ expanded }}>
          <Grid container spacing={1.5} sx={{ width: '100%' }}>
            {props?.children}
          </Grid>
        </StyledAccordianDetails>
      </StyledAccordian>
    </StyledAccordionWrapper>
  );
};

ChartAccordion.propTypes = {
  label: PropTypes.string.isRequired,
  children: CustomPropTypes.children,
};

export default ChartAccordion;

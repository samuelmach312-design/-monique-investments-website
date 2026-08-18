///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import { styled } from '@mui/material/styles';
import { Box, Card, CardContent, CardHeader } from '@mui/material';
import PropTypes from 'prop-types';
import EmptyPanelMessage from 'sources/components/EmptyPanelMessage';

const StyledCard = styled(Card)(({theme}) => ({
  border: '1px solid '+theme.otherVars.borderColor,
  height: '100%',
  '& .StackedBarContainer-cardContent': {
    padding: theme.spacing(0.5, 1),
    height: theme.spacing(22.5),
    display: 'flex',
  },
}));

export default function StackedBarContainer(props) {

  return (
    <StyledCard elevation={0} data-testid="bar-container">
      {props.title && <CardHeader title={<Box>
        <div id={props.id}>{props.title}</div>
      </Box>} /> }
      <CardContent className='StackedBarContainer-cardContent'>
        {!props.errorMsg && !props.isTest && props.children}
        {props.errorMsg && <EmptyPanelMessage text={props.errorMsg}/>}
      </CardContent>
    </StyledCard>
  );
}

StackedBarContainer.propTypes = {
  id: PropTypes.string.isRequired,
  title: PropTypes.string,
  children: PropTypes.node.isRequired,
  errorMsg: PropTypes.string,
  isTest: PropTypes.bool
};

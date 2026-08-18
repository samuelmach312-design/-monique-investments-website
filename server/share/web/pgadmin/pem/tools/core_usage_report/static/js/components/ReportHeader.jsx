///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////


import React from 'react';
import PropTypes from 'prop-types';
import { Box, Typography } from '@mui/material';
import CalendarTodayIcon from '@mui/icons-material/CalendarToday';
import { styled } from '@mui/material/styles';

const StyledHeaderContainer = styled(Box)(({ theme }) => ({
  padding: theme.spacing(1),
  border: `1px solid ${theme.palette.divider}`,
  borderRadius: theme.shape.borderRadius,
  backgroundColor: theme.otherVars.report.cardBg,
  display: 'flex',
  flexDirection: 'column',
  gap: theme.spacing(2),
  marginTop: theme.spacing(0.5),
}));

const StyledTitle = styled(Typography)(({ theme }) => ({
  fontWeight: theme.typography.fontWeightBold,
}));

const StyledInfo = styled(Typography)(({ theme }) => ({
  display: 'flex',
  alignItems: 'center',
  gap: theme.spacing(1),
}));

const ReportHeader = (props) => {
  const { title, generatedOn, pemInfo, labels } = props;

  return (
    <StyledHeaderContainer>
      <StyledTitle variant="h5">{title}</StyledTitle>
      <StyledInfo variant="body1">
        <CalendarTodayIcon fontSize="small" />
        {labels.generated_on}: {generatedOn} &nbsp; | &nbsp; {labels.using}:{' '}
        {pemInfo.name} {labels.version}: {pemInfo.version}
      </StyledInfo>
    </StyledHeaderContainer>
  );
};


ReportHeader.propTypes = {
  title: PropTypes.string.isRequired,
  generatedOn: PropTypes.string.isRequired,
  pemInfo: PropTypes.shape({
    name: PropTypes.string.isRequired,
    version: PropTypes.string.isRequired,
  }).isRequired,
  labels: PropTypes.shape({
    header: PropTypes.string,
    generated_on: PropTypes.string.isRequired,
    using: PropTypes.string.isRequired,
    version: PropTypes.string.isRequired,
  }).isRequired,
};

export default ReportHeader;

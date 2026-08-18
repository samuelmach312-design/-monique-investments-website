///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState } from 'react';
import PropTypes from 'prop-types';
import { Typography, MenuItem, Select, FormControl } from '@mui/material';
import CalendarTodayIcon from '@mui/icons-material/CalendarToday';
import {
  StyledHeaderContainer,
  StyledInfoContainer,
  StyledDropdownContainer,
  StyledTitle,
  StyledInfo,
} from './StyledComponents';

const ReportHeader = ({ generatedOn, title, labels, sectionRefs = [] }) => {
  
  const [selectedSection, setSelectedSection] = useState(
    sectionRefs.length > 0 ? sectionRefs[0].label : ''
  );

  const handleSectionChange = (event) => {
    const selectedValue = event.target.value;
    setSelectedSection(selectedValue);

    const selectedRef = sectionRefs.find(
      (section) => section.label === selectedValue
    );
    selectedRef?.ref.current?.scrollIntoView({ behavior: 'smooth' });
  };

  return (
    <StyledHeaderContainer>
      <StyledInfoContainer>
        <StyledTitle variant="h5">{title}</StyledTitle>
        <StyledInfo variant="body1">
          <CalendarTodayIcon fontSize="small" />
          {labels.generated_on} : {generatedOn}
        </StyledInfo>
      </StyledInfoContainer>

      {sectionRefs.length > 0 && (
        <StyledDropdownContainer>
          <Typography variant="body2">{labels.go_to_text}</Typography>
          <FormControl size="small">
            <Select
              value={selectedSection}
              onChange={handleSectionChange}
              displayEmpty
            >
              {sectionRefs.map(({ label }) => (
                <MenuItem key={label} value={label}>
                  {labels[label] || label}
                </MenuItem>
              ))}
            </Select>
          </FormControl>
        </StyledDropdownContainer>
      )}
    </StyledHeaderContainer>
  );
};

ReportHeader.propTypes = {
  generatedOn: PropTypes.string.isRequired,
  title: PropTypes.string.isRequired,
  labels: PropTypes.shape({
    go_to_text: PropTypes.string.isRequired,
    generated_on: PropTypes.string.isRequired,
  }).isRequired,
  sectionRefs: PropTypes.arrayOf(
    PropTypes.shape({
      label: PropTypes.string.isRequired,
      ref: PropTypes.shape({
        current: PropTypes.instanceOf(Element),
      }).isRequired,
    })
  ).isRequired,
};

export default ReportHeader;

///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState } from 'react';
import PropTypes from 'prop-types';
import Typography from '@mui/material/Typography';
import MenuItem from '@mui/material/MenuItem';
import Select from '@mui/material/Select';
import FormControl from '@mui/material/FormControl';
import CalendarTodayIcon from '@mui/icons-material/CalendarToday';
import {
  StyledHeaderContainer,
  StyledInfoContainer,
  StyledDropdownContainer,
  StyledTitle,
  StyledInfo,
} from './StyledComponents';

const ReportHeader = ({ generatedOn, labels, sectionRefs = [] }) => {
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
        <StyledTitle variant="h5">{labels.header}</StyledTitle>
        <StyledInfo variant="body1">
          <CalendarTodayIcon fontSize="small" />
          {labels.generated_on}: {generatedOn}
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
  labels: PropTypes.shape({
    header: PropTypes.string.isRequired,
    generated_on: PropTypes.string.isRequired,
    go_to_text: PropTypes.string.isRequired,
    pem_agents: PropTypes.string.isRequired,
    pem_server_dir: PropTypes.string.isRequired,
    table_sizes: PropTypes.string.isRequired,
  }).isRequired,
  sectionRefs: PropTypes.oneOfType([PropTypes.array, PropTypes.object])
    .isRequired,
};

export default ReportHeader;

///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import AddSection from './AddSection';
import {
  AddSectionPlaceholder,
  AddSectionIcon,
} from 'pem/modules/Monitoring/Common/StyledComponents';
import { addSection } from 'pem/modules/Monitoring/Common/utils';
import { BreadcrumbConstants } from '../../Common/constants';

const CreateDashboardPanel = ({
  designLayout,
  setCustomDashboardSchema,
  chartList,
  selectedSectionHandler,
  editSection,
}) => {
  return (
    <>
      {designLayout.map((section, index) => (
        <AddSection
          sectionDetails={section}
          setCustomDashboardSchema={setCustomDashboardSchema}
          numberOfSections={designLayout.length}
          key={index}
          chartList={chartList}
          selectedSectionHandler={selectedSectionHandler}
          editSection={editSection}
        />
      ))}
      <AddSectionPlaceholder
        aria-label={BreadcrumbConstants.ADD_SECTION}
        onClick={() => addSection(setCustomDashboardSchema)}
      >
        <span>
          <AddSectionIcon /> {BreadcrumbConstants.ADD_SECTION}
        </span>
      </AddSectionPlaceholder>
    </>
  );
};

CreateDashboardPanel.propTypes = {
  designLayout: PropTypes.array.isRequired,
  chartList: PropTypes.array.isRequired,
  setCustomDashboardSchema: PropTypes.func.isRequired,
  selectedSectionHandler: PropTypes.func.isRequired,
  editSection: PropTypes.func.isRequired,
};

export default CreateDashboardPanel;

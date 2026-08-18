///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import Grid from '@mui/material/Grid';
import AddCircleOutlineIcon from '@mui/icons-material/AddCircleOutline';
import gettext from 'sources/gettext';
import {
  StyledIconButton,
  SectionContainer,
  ChartsContainer,
  ChartPlaceholder,
  StyledPrimaryButton,
  StyledOutlinedInput,
  SectionPlaceholderLayout,
  Delete,
  EditSectionIcon,
} from 'pem/modules/Monitoring/Common/StyledComponents';
import AddChart from './AddChart';
import {
  deleteSection,
  updateSectionName,
} from 'pem/modules/Monitoring/Common/utils';
import { BreadcrumbConstants } from 'pem/modules/Monitoring/Common/constants';

const AddSection = ({
  sectionDetails,
  setCustomDashboardSchema,
  numberOfSections,
  chartList,
  selectedSectionHandler,
  editSection,
}) => {
  return (
    <SectionContainer>
      <SectionPlaceholderLayout
        container
        spacing={2}
        alignItems='center'
        justifyContent='space-between'
        sx={{ width: '100%' }}
      >
        <Grid size={4}>
          <StyledOutlinedInput
            id='outlined-basic'
            placeholder='Section name'
            data-testid='section-name'
            variant='outlined'
            aria-label={gettext('Section Name')}
            value={sectionDetails?.sec_title}
            onChange={(e) =>
              updateSectionName(
                setCustomDashboardSchema,
                sectionDetails?.sec_id,
                e.target.value
              )
            }
            search='true'
          />
        </Grid>
        <Grid size={1.5}>
          <Grid
            container
            spacing={1}
            justifyContent='flex-end'
            alignItems='center'
            direction='row'
          >
            <Grid>
              <StyledIconButton
                variant='text'
                aria-haspopup='listbox'
                aria-controls='settings-menu'
                aria-label={gettext('Delete section button')}
                disabled={numberOfSections === 1}
                onClick={() =>
                  deleteSection(
                    setCustomDashboardSchema,
                    sectionDetails?.sec_id
                  )
                }
              >
                <Delete />
              </StyledIconButton>
            </Grid>
            {sectionDetails?.charts.length > 0 && (
              <Grid>
                <StyledIconButton
                  variant='text'
                  aria-haspopup='listbox'
                  aria-controls='settings-menu'
                  aria-label={gettext('Edit section button')}
                  onClick={() =>
                    editSection(
                      sectionDetails?.sec_title,
                      sectionDetails?.sec_id
                    )
                  }
                >
                  <EditSectionIcon />
                </StyledIconButton>
              </Grid>
            )}
          </Grid>
        </Grid>
      </SectionPlaceholderLayout>

      <ChartsContainer container spacing={2} sx={{ width: '100%' }}>
        {sectionDetails?.charts.length === 0 ? (
          <Grid size={12}>
            <ChartPlaceholder>
              <StyledPrimaryButton
                startIcon={<AddCircleOutlineIcon />}
                aria-label={BreadcrumbConstants.SELECT_CHARTS}
                onClick={() => {
                  selectedSectionHandler(
                    sectionDetails?.sec_title,
                    sectionDetails?.sec_id
                  );
                }}
              >
                {BreadcrumbConstants.SELECT_CHARTS}
              </StyledPrimaryButton>
            </ChartPlaceholder>
          </Grid>
        ) : (
          sectionDetails?.charts.map((chart, index) => (
            <AddChart
              key={index}
              chartInfo={chart}
              sectionID={sectionDetails?.sec_id}
              setCustomDashboardSchema={setCustomDashboardSchema}
              chartList={chartList}
            />
          ))
        )}
      </ChartsContainer>
    </SectionContainer>
  );
};

AddSection.propTypes = {
  setCustomDashboardSchema: PropTypes.func.isRequired,
  numberOfSections: PropTypes.number.isRequired,
  chartList: PropTypes.array.isRequired,
  selectedSectionHandler: PropTypes.func.isRequired,
  sectionDetails: PropTypes.object.isRequired,
  editSection: PropTypes.func.isRequired,
};

export default AddSection;

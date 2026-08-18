///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import CardContent from '@mui/material/CardContent';
import AddCircleOutlineIcon from '@mui/icons-material/AddCircleOutline';
import CheckCircleOutlineIcon from '@mui/icons-material/CheckCircleOutline';
import gettext from 'sources/gettext';
import {
  AddChartButton,
  InfoTag,
  ChartCardWrapper,
  StyledChartCard,
  ChartCardHeader,
  ChartCardName,
  ChartCardCategoryChip,
  ChartCardContent,
  ChartCardKey,
} from 'pem/modules/Monitoring/Common/StyledComponents';
import MarkdownParser from 'pem/modules/Monitoring/Common/MarkdownParser';
import { BreadcrumbConstants } from 'pem/modules/Monitoring/Common/constants';

const ChartCard = ({ chartInfo, handleAddChart, isChartSelected }) => {
  return (
    <ChartCardWrapper>
      <StyledChartCard data-testid={gettext(chartInfo?.name)}>
        <ChartCardHeader
          action={
            isChartSelected(chartInfo?.cid) ? (
              <InfoTag
                startIcon={<CheckCircleOutlineIcon />}
                aria-label={BreadcrumbConstants.ADDED}
              >
                {BreadcrumbConstants.ADDED}
              </InfoTag>
            ) : (
              <AddChartButton
                startIcon={<AddCircleOutlineIcon />}
                aria-label={BreadcrumbConstants.ADD_CHART}
                onClick={() => {
                  handleAddChart(chartInfo);
                }}
              >
                {BreadcrumbConstants.ADD_CHART}
              </AddChartButton>
            )
          }
          title={
            <span>
              <ChartCardName>{gettext(chartInfo?.name)}</ChartCardName>
              <ChartCardCategoryChip
                label={gettext(chartInfo?.category)}
                variant='outlined'
                size='small'
                sx={{ background: chartInfo?.color }}
              />
            </span>
          }
        />
        <CardContent>
          <ChartCardContent variant='body2'>
            <ChartCardKey>{gettext('Type: ')}</ChartCardKey>
            {gettext(chartInfo?.type)}
          </ChartCardContent>
          <ChartCardContent variant='body2'>
            <ChartCardKey>{gettext('Level: ')}</ChartCardKey>
            {gettext(chartInfo?.level)}
          </ChartCardContent>
          {chartInfo?.description?.trim() && (
            <ChartCardContent variant='body2'>
              <ChartCardKey>{gettext('Description: ')}</ChartCardKey>
              <MarkdownParser description={chartInfo?.description} />
            </ChartCardContent>
          )}
        </CardContent>
      </StyledChartCard>
    </ChartCardWrapper>
  );
};

ChartCard.propTypes = {
  isChartSelected: PropTypes.func.isRequired,
  chartInfo: PropTypes.object.isRequired,
  handleAddChart: PropTypes.func.isRequired,
};

export default ChartCard;

///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import Card from '@mui/material/Card';
import CardContent from '@mui/material/CardContent';
import Grid from '@mui/material/Grid';
import Typography from '@mui/material/Typography';
import PropTypes from 'prop-types';
import gettext from 'sources/gettext';
import { StyledGrid } from 'pem/modules/info_tile_component/common/styledComponents';

const InfoTileCard = ({ icon: IconComponent, label, value, id }) => {
  return (
    <StyledGrid size={3}>
      <Card
        className='CardStyled'
        elevation={0}
      >
        <CardContent>
          <Grid
            container
            className='GridContainer'
            alignItems='center'
            wrap='nowrap'
          >
            <Grid>
              <IconComponent />
            </Grid>
            <Grid data-testid={`${id}-component`}>
              <Typography
                variant='subtitle1'
                className='LabelText'
                aria-label={gettext(label)}
              >
                {gettext(label)}
              </Typography>
              <Typography
                variant='body2'
                className='ValueText'
                data-testid={`${id}-value`}
              >
                {gettext(value)}
              </Typography>
            </Grid>
          </Grid>
        </CardContent>
      </Card>
    </StyledGrid>
  );
};

InfoTileCard.propTypes = {
  icon: PropTypes.elementType.isRequired,
  label: PropTypes.string.isRequired,
  value: PropTypes.string.isRequired,
  id: PropTypes.string.isRequired,
};

export default InfoTileCard;

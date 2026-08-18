///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import InfoTileCard from 'pem/modules/info_tile_component/info_tile_card/InfoTileCard';
import { initTileData } from 'pem/modules/info_tile_component/common/constants';
import { StyledInfoTileGrid } from 'pem/modules/text_component/common/styledComponents';
import { generateInfoTileSchema } from 'pem/modules/info_tile_component/common/utils';

const InfoTileComponent = ({ infoTileData = initTileData }) => {
  const infoTileSchema = generateInfoTileSchema(infoTileData);
  return (
    <StyledInfoTileGrid container spacing={2}>
      {infoTileSchema.map((tile, id) => (
        <InfoTileCard
          key={id}
          id={tile.id}
          icon={tile.icon}
          label={tile.label}
          value={tile.value}
        />
      ))}
    </StyledInfoTileGrid>
  );
};

InfoTileComponent.propTypes = {
  infoTileData: PropTypes.object,
};

export default InfoTileComponent;

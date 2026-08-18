///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useContext } from 'react';

import Box from '@mui/material/Box';
import RecyclingRoundedIcon from '@mui/icons-material/RecyclingRounded';

import { DefaultButton } from 'sources/components/Buttons';
import CustomPropTypes from 'sources/custom_prop_types';
import gettext from 'sources/gettext';
import { SchemaStateContext } from 'sources/SchemaView/SchemaState/index';
import {
  SearchBox,
} from 'sources/SchemaView/DataGridView/SearchBox';
import { DataGridContext } from 'sources/SchemaView/DataGridView/context';

import {
  DataGridTopHeaderStyles,
  GridHeaderMiddle,
} from 'pem/modules/PemComponents/StyledComponents';

export function ProbeConfigHeader() {
  const {field}= useContext(DataGridContext);
  const schemaState = useContext(SchemaStateContext);

  const onRefreshClick = () => {
    field?.onRefresh(schemaState);
  };

  return (
    <Box>
      <DataGridTopHeaderStyles>
        <Box className="DataGridView-topHeader">
          <GridHeaderMiddle className="DataGridView-gridHeader-middle">
            <SearchBox />
          </GridHeaderMiddle>
          <Box className="DataGridView-importButton">
            <DefaultButton
              data-test="import-button"
              onClick={onRefreshClick}
              startIcon={<RecyclingRoundedIcon />}
              className="Dialog-buttonMargin"
              disabled={!field.canReset}
            >
              {gettext('Reset')}
            </DefaultButton>
          </Box>
        </Box>
      </DataGridTopHeaderStyles>
    </Box>
  );
}

ProbeConfigHeader.propTypes = {
  tableEleRef: CustomPropTypes.ref,
};

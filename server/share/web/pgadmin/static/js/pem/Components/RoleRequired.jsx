///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import { Box } from '@mui/material';

import { MESSAGE_TYPE, NotifierMessage } from
  'sources/components/FormComponents.jsx';


export default function RoleRequired(props) {
  return (
    <Box>
      <NotifierMessage
        type={MESSAGE_TYPE.ERROR} message={props.message}
        closable={false} textCenter={true}/>
    </Box>
  );
}

RoleRequired.propTypes = {
  message: PropTypes.string,
};

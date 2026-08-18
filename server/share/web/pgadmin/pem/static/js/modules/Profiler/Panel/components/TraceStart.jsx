////////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
////////////////////////////////////////////////////////////////////////////////

import { Box, styled } from '@mui/material';
import React, { useState } from 'react';
import { DefaultButton, PrimaryButton } from '../../../../../../../static/js/components/Buttons';
import PropTypes from 'prop-types';
import gettext from 'sources/gettext';

import CloseIcon from '@mui/icons-material/CloseRounded';
import CheckRoundedIcon from '@mui/icons-material/CheckRounded';
import { InputText } from '../../../../../../../static/js/components/FormComponents';


const Root = styled('div')(({theme})=>({
  display: 'flex',
  flexDirection: 'column',
  height: '100%',
  flexGrow: 1,

  '& .TraceStart-content': {
    padding: '0.5rem',
  },

  '& .TraceStart-footer': {
    borderTop: `1px solid ${theme.otherVars.inputBorderColor} !important`,
    padding: '0.5rem',
    display: 'flex',
    width: '100%',
    background: theme.otherVars.headerBg,
    alignItems: 'center',

    '& .TraceStart-actions': {
      marginLeft: 'auto',
      gap: '4px',
      display: 'flex',
      alignItems: 'center',
    }
  }
}));

export default function TraceStart({onOK, onClose}) {
  const [logMin, setLogMin] = useState(0);
  const onStart = async ()=>{
    onOK?.(logMin);
    onClose();
  };

  return (
    <Root>
      <Box className='TraceStart-content'>
        <Box>{gettext('New trace with same data will be created and loaded. Do you wish to continue?')}</Box>
        <br/>
        <Box>
          <span>{gettext('Enter the minimum duration of query(ms) to be used when the profiler is restarted:')}</span>
          <InputText type="int" value={logMin} onChange={(v)=>setLogMin(v)} />
        </Box>
      </Box>
      <Box className='TraceStart-footer'>
        <Box className="TraceStart-actions">
          <DefaultButton startIcon={<CloseIcon />} onClick={onClose} >{gettext('Close')}</DefaultButton>
          <PrimaryButton startIcon={<CheckRoundedIcon />} onClick={onStart}
            disabled={false}>
            {gettext('Start')}
          </PrimaryButton>
        </Box>
      </Box>
    </Root>
  );
}

TraceStart.propTypes = {
  onOK: PropTypes.func,
  onClose: PropTypes.func,
};


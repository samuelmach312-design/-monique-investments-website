///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState } from 'react';
import PropTypes from 'prop-types';
import { InputLabel, styled } from '@mui/material';

import gettext from 'sources/gettext';
import { InputText } from 'sources/components/FormComponents';

import DialogBox from './DialogBox';

const StyledInputLabel = styled(InputLabel)(({ theme }) => ({
  margin: `${theme.spacing(0.5)} 0`,
}));

const DialogContainer = styled('div')(({ theme }) => ({
  padding: theme.spacing(1),
  gap: theme.spacing(0.5),
}));

export default function RenameDialog({
  closeDialog,
  value,
  onOkClick,
  inputLabel = gettext('Enter input'),
}) {
  const [name, setName] = useState(value);
  const handleOk = () => {
    if (onOkClick) {
      onOkClick(name);
    }
    closeDialog();
  };
  return (
    <DialogBox onCancel={closeDialog} onOk={handleOk}>
      <DialogContainer>
        <StyledInputLabel>{inputLabel}</StyledInputLabel>
        <InputText value={name} onChange={(val) => setName(val)} />
      </DialogContainer>
    </DialogBox>
  );
}

RenameDialog.propTypes = {
  closeDialog: PropTypes.func.isRequired,
  value: PropTypes.string,
  onOkClick: PropTypes.func,
  inputLabel: PropTypes.string.isRequired,
};

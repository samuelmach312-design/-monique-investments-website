///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import { ModalContent, ModalFooter } from 'sources/components/ModalContent';
import { DefaultButton, PrimaryButton } from 'sources/components/Buttons';
import CloseIcon from '@mui/icons-material/Close';
import DoneIcon from '@mui/icons-material/Done';
import gettext from 'sources/gettext';

export default function DialogBox({
  children,
  onCancel,
  onOk,
  okLabel = gettext('OK'),
  cancelLabel = gettext('Cancel'),
  hideCancel = false,
  hideOk = false,
  okDisabled = false,
}) {
  return (
    <ModalContent>
      {children}
      <ModalFooter>
        {!hideCancel && (
          <DefaultButton startIcon={<CloseIcon />} onClick={onCancel}>
            {cancelLabel}
          </DefaultButton>
        )}
        {!hideOk && (
          <PrimaryButton
            startIcon={<DoneIcon />}
            disabled={okDisabled}
            onClick={() => {
              onOk();
              onCancel();
            }}
          >
            {okLabel}
          </PrimaryButton>
        )}
      </ModalFooter>
    </ModalContent>
  );
}

DialogBox.propTypes = {
  children: PropTypes.node,
  onCancel: PropTypes.func.isRequired,
  onOk: PropTypes.func.isRequired,
  okLabel: PropTypes.string,
  cancelLabel: PropTypes.string,
  hideCancel: PropTypes.bool,
  hideOk: PropTypes.bool,
  okDisabled: PropTypes.bool,
};

/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2025, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import gettext from 'sources/gettext';

import { Box } from '@mui/material';
import CloseIcon from '@mui/icons-material/CloseRounded';

import { DefaultButton } from '../components/Buttons';
import { ModalContent, ModalFooter }from '../../../static/js/components/ModalContent';

export default function UrlDialogContent({ url, onClose }) {
  return (
    <ModalContent>
      <Box flexGrow="1">
        <iframe src={url} title=" " width="100%" height="100%" onLoad={(e)=>{
          e.target?.contentWindow?.focus();
        }}/>
      </Box>
      <ModalFooter>
        <DefaultButton data-test="close" startIcon={<CloseIcon />} onClick={() => {
          onClose();
        }} >{gettext('Close')}</DefaultButton>
      </ModalFooter>
    </ModalContent>
  );
}

UrlDialogContent.propTypes = {
  url: PropTypes.string,
  onClose: PropTypes.func,
};

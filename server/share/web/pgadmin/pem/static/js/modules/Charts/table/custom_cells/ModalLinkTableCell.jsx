///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import SchemaView from 'sources/SchemaView';
import url_for from 'sources/url_for';
import gettext from 'sources/gettext';
import { saveData } from 'pem/utils/actionFunctions';
import { treatSavePayload } from 'pem/modules/Alerts/Config/utils';
import { ModalLinkTableCellCollectionSchema } from './modalLinkTableCell.ui';
import { ENDPOINTS } from 'pem/common/constants';
import { MESSAGES } from 'pem/modules/Alerts/ServerConfigs/constants';

function ModalLinkTableCell({ closeDialog, templateParams, initialData }) {


  const modalLinkTableCellSchema = React.useRef(null);
  if (!modalLinkTableCellSchema.current) {
    modalLinkTableCellSchema.current = new ModalLinkTableCellCollectionSchema(
      templateParams,
      { dialog: true }
    );
  }

  const getInitData = () => {
    return Promise.resolve(initialData);
  };

  const onHelp = () => {
    window.open(
      url_for(ENDPOINTS.HELP, {
        filename: ENDPOINTS.ALERTS.SERVER_CONFIG.HELP,
      })
    );
  };

  return (
    <SchemaView
      formType='dialog'
      getInitData={getInitData}
      viewHelperProps={{ mode: 'edit' }}
      schema={modalLinkTableCellSchema.current}
      showFooter={true}
      isTabView={true}
      onSave={(isNew, data) => {
        return saveData(
          url_for('alerts.save'),
          {
            data: { changed: [data]},
            target: templateParams.alert_node_info,
            isDialog: true,
          },
          gettext(MESSAGES.SUCCESS),
          treatSavePayload,
          closeDialog
        );
      }}
      disableSqlHelp={true}
      disableDialogHelp={true}
      onHelp={onHelp}
      onClose={closeDialog}
    />
  );
}

ModalLinkTableCell.propTypes = {
  closeDialog: PropTypes.func,
  alertId: PropTypes.number,
  templateParams: PropTypes.object,
  initialData: PropTypes.object
};

export default ModalLinkTableCell;

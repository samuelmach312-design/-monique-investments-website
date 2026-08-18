///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import gettext from 'sources/gettext';
import pgAdmin from 'sources/pgadmin';
import MonitoringPanel from 'pem/monitoring/Config';
import { openTab } from 'pem/utils/helpers';
import { FIELD_TYPES } from 'pem/common/constants';
import {
  register_pem_custom_cell,
  register_pem_custom_control,
} from 'sources/SchemaView/PEMMappedControl';
import {
  StatusIconCell,
  TimeInputCell,
  ButtonCell,
  SyncWidget
} from 'pem/common/ControlComponents/PemCustomCells';
import { ProgressStatusButton } from 'pem/common/ControlComponents/PemCustomControls';
import { PEM_PANELS, PEM_MANAGE_PANELS, PEM_TOOL_PANELS } from './constants';

const pemPanelData = [
  {
    id: PEM_PANELS.MONITORING,
    title: gettext('Monitoring'),
    closable: false,
    cache: false,
    content: <MonitoringPanel />,
  },
];

function openDefaultPanels(workspaceEnabled) {
  // If enabled - Default panels are already loaded in 'manage' workspace.
  if (workspaceEnabled) {
    // Forcefully close the default panels from the default workspace
    // (if opened).
    pemPanelData.forEach((panel) => {
      pgAdmin.Browser.docker.default_workspace.close(panel.id, true);
    });
  }

  pemPanelData.forEach((panel) =>
    openTab({
      panelId: panel.id,
      ...panel,
      closable: true,
    })
  );
}

// Register the custom cell renderer here
register_pem_custom_cell(FIELD_TYPES.STATUS_ICON, StatusIconCell);
register_pem_custom_cell(FIELD_TYPES.TIME, TimeInputCell);
register_pem_custom_cell(FIELD_TYPES.ACTION_BUTTON, ButtonCell);
register_pem_custom_cell(FIELD_TYPES.SYNC_WIDGET, SyncWidget);

// register the custom form controls here
register_pem_custom_control(FIELD_TYPES.PROGRESS_STATUS_BUTTON, ProgressStatusButton);

export {
  PEM_PANELS,
  PEM_MANAGE_PANELS,
  PEM_TOOL_PANELS,
  pemPanelData,
  openDefaultPanels,
};

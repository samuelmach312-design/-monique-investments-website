////////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
////////////////////////////////////////////////////////////////////////////////

import { BROWSER_PANELS, WORKSPACES } from  'pgbrowser/constants';
import {
  PEM_MANAGE_PANELS, PEM_TOOL_PANELS, pemPanelData,
} from 'pem/Panels';

export const pem_config = [{
  docker: 'pem_manage_workspace',
  panel: PEM_MANAGE_PANELS,
  workspace: WORKSPACES.PEM_MANAGE,
  layout: {
    dockbox: {
      mode: 'vertical',
      children: [
        {
          mode: 'horizontal',
          children: [
            {
              size: 100,
              id: BROWSER_PANELS.MAIN,
              group: 'playground',
              tabs: [...pemPanelData],
              panelLock: {panelStyle: 'playground'},
            }
          ]
        },
      ]
    }
  }
}, {
  docker: 'pem_tools_workspace',
  panel: PEM_TOOL_PANELS,
  workspace: WORKSPACES.PEM_TOOLS,
  layout: {
    dockbox: {
      mode: 'vertical',
      children: [
        {
          mode: 'horizontal',
          children: [
            {
              size: 100,
              id: BROWSER_PANELS.MAIN,
              group: 'playground',
              tabs: [],
              panelLock: {panelStyle: 'playground'},
            }
          ]
        },
      ]
    }
  }
}];

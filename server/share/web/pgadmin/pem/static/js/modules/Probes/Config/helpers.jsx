///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';

import pgAdmin from 'sources/pgadmin';
import gettext from 'sources/gettext';

import checkPrivilege from 'pgbrowser/checkPrivilege';
import { PEM_PANELS } from 'pem/Panels/constants';
import CustomProbes from 'pem/modules/Probes/CustomProbes/Component';
import CheckBoxTreeModal from 'pem/components/check_box_tree_modal';
import { getCopySourceNodeInfo, openTab } from 'pem/utils/helpers';


export const openManageProbes = () => {
  checkPrivilege(
    { label: gettext('Manage Probes'), privilege: 'pem_manage_probe' },
    () => {
      openTab({
        panelId: PEM_PANELS.CUSTOM_PROBES,
        title: gettext('Manage Probes'),
        content: <CustomProbes />,
        closable: true,
        cache: false,
        toolUrl: '/monitoring/custom-probes'
      });
    }
  );
};

export const openCopyProbeConfiguration = () => {
  checkPrivilege(
    {
      label: gettext('Copy Probe Configurations'),
      privilege: 'pem_config_probe'
    },
    () => {
      // Retrives data of selected node from Nodes
      const _node = pgAdmin.Browser?.tree?.selected();
      if (!_node) return;
      if (_node._metadata.data._type.includes('coll-')) return;

      const sourceNode = getCopySourceNodeInfo(_node);

      pgAdmin.Browser.notifier.showModal(
        gettext(`Copy Probe Configurations from ${sourceNode.label}`),
        (closeDialog) => {
          return (
            <CheckBoxTreeModal
              type={gettext('probes')}
              title={gettext('Probes')}
              sourceNode={sourceNode}
              closeDialog={closeDialog}
            />
          );
        },
        {
          isFullScreen: false,
          isResizeable: true,
          showFullScreen: true,
          isFullWidth: true,
          dialogWidth: pgAdmin.Browser.stdW.md,
          dialogHeight: pgAdmin.Browser.stdH.md,
        }
      );
    }
  );
};

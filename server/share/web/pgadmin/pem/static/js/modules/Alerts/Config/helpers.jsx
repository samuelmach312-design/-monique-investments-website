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
import AlertTemplates from 'pem/modules/Alerts/AlertTemplates';
import EmailGroup from 'pem/modules/Alerts/EmailGroup/Component';
import EmailTemplates from 'pem/modules/Alerts/EmailTemplates/Component';
import ServerConfigs from 'pem/modules/Alerts/ServerConfigs/Component';
import Webhooks from 'pem/modules/Alerts/Webhooks';
import CheckBoxTreeModal from 'pem/components/check_box_tree_modal';
import { getCopySourceNodeInfo, openTab  } from 'pem/utils/helpers';


export const openServerConfig = () => {
  checkPrivilege(
    { label: gettext('Server Configuration'), privilege: 'pem_config' },
    () => {
      const pgBrowser = pgAdmin.Browser;
      pgBrowser.notifier.showModal(
        gettext('Server Configuration'),
        (closeDialog) => {
          return <ServerConfigs closeDialog={() => closeDialog()} />;
        },
        {
          isFullScreen: true,
          isResizeable: true,
          showFullScreen: true,
          isFullWidth: true,
          dialogWidth: pgBrowser.stdW.lg,
          dialogHeight: pgBrowser.stdH.lg,
        }
      );
    }
  );
};

export const openWebhooks = () => {
  checkPrivilege(
    { label: gettext('Webhooks'), privilege: 'pem_config' },
    () => {
      openTab({
        panelId: PEM_PANELS.WEBHOOKS,
        title: gettext('Webhooks'),
        content: <Webhooks />,
        closable: true,
        cache: false,
      });
    }
  );
};

export const openEmailGroup = () => {
  checkPrivilege(
    { label: gettext('Email Groups'), privilege: 'pem_config' },
    () => {
      openTab({
        panelId: PEM_PANELS.EMAIL_GROUP,
        title: gettext('Email Groups'),
        content: <EmailGroup />,
        closable: true,
        cache: false,
      });
    }
  );
};

export const openEmailTemplates = () => {
  checkPrivilege(
    { label: gettext('Email Templates'), privilege: 'pem_config' },
    () => {
      openTab({
        panelId: PEM_PANELS.EMAIL_TEMPLATES,
        title: gettext('Email Templates'),
        content: <EmailTemplates />,
        closable: true,
        cache: false,
        group: 'playground',
      });
    }
  );
};

export const openAlertTemplates = () => {
  checkPrivilege(
    { label: gettext('Alert Templates'), privilege: 'pem_manage_alert' },
    () => {
      openTab({
        panelId: PEM_PANELS.ALERT_TEMPLATE,
        title: gettext('Alert Templates'),
        content: <AlertTemplates />,
        closable: true,
        cache: false,
        group: 'playground',
      });
    }
  );
};

export const openCopyAlert = () => {
  checkPrivilege(
    { label: gettext('Copy Alerts'), privilege: 'pem_config_alert' },
    () => {
      const pgBrowser = pgAdmin.Browser;

      // Retrives data of selected node from Nodes
      const _node = pgBrowser?.tree?.selected();

      if (!_node) return;
      if (_node._metadata.data._type.includes('coll-')) return;

      const sourceNode = getCopySourceNodeInfo(_node);

      pgBrowser.notifier.showModal(
        gettext(`Copy Alerts from ${sourceNode.label}`),
        (closeDialog) => {
          return (
            <CheckBoxTreeModal
              type="alerts"
              title={gettext('Alerts')}
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
          dialogWidth: pgBrowser.stdW.md,
          dialogHeight: pgBrowser.stdH.md,
        }
      );
    }
  );
};

///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState } from 'react';
import Menu from '@mui/material/Menu';
import PropTypes from 'prop-types';
import {
  StyledBreadcrumbButton,
  StyledMenuItem,
  StyledAddIcon,
  StyledShareIcon,
  StyledEditIcon,
  StyledDeleteIcon,
  StyledExportIcon,
  StyledImportIcon,
  StyledKebabIcon,
} from 'pem/modules/Monitoring/Common/StyledComponents';
import { usePgAdmin } from 'sources/PgAdminProvider';
import getApiInstance from 'sources/api_instance';
import url_for from 'sources/url_for';
import withPEMRoleCheck from 'sources/pem/helpers/withPEMRoleCheck';
import ImportCustomDashboard from './ImportCustomDashboard';
import { generateRandomNumber, getMenuLabel } from 'pem/common/utils';
import gettext from 'sources/gettext';
import { BreadcrumbConstants } from 'pem/modules/Monitoring/Common/constants';

const SettingsSection = ({
  setShowSettings,
  setShowSharePermissions,
  disabledForInbuiltDashboard,
  openCustomDashboardEditor,
  level,
  currentSelection,
  deleteCustomDashboard,
  fetchDashboardContent,
}) => {
  const [anchorEl, setAnchorEl] = useState(null);
  const pgAdmin = usePgAdmin();
  const api = getApiInstance();

  const handleClose = () => {
    setAnchorEl(null);
  };

  const exportCustomDashboard = () => {
    api
      .post(url_for(BreadcrumbConstants.EXPORT_CUSTOM_DASHBOARD_URL), {
        dashboards: [currentSelection.id],
      })
      .then(({ data }) => {
        const fileTime = Date.now();
        const a = document.createElement('a');
        a.setAttribute('id', `ca_download_${fileTime}`);
        const jsonData = JSON.stringify(data);
        a.href = URL.createObjectURL(
          new Blob([jsonData], { type: 'application/json' })
        );
        a.download = `Export_Custom_Dashboards_${fileTime}.pemdash`;
        a.click();
      })
      .catch((err) => {
        if (err?.response) {
          console.error('error resp', err?.response);
        } else if (err?.request) {
          console.error('error req', err?.request);
        } else if (err?.message) {
          console.error('error msg', err?.message);
        }
        console.error(err);
      });
  };

  return (
    <>
      <StyledBreadcrumbButton
        id='select-button-settings'
        variant='text'
        aria-haspopup='listbox'
        aria-controls='select-menu'
        data-testid='breadcrumb-more-button'
        aria-label={BreadcrumbConstants.MORE_MENU_BUTTON}
        aria-expanded={anchorEl ? 'true' : undefined}
        onClick={(e) => setAnchorEl(e?.currentTarget)}
        $lastitem={false}
        inputprops={{ 'data-testid': 'breadcrumb-more-button' }}
        sx={{ paddingLeft: 0 }}
      >
        <StyledKebabIcon />
      </StyledBreadcrumbButton>
      <Menu
        id='select-menu-settings'
        anchorEl={anchorEl}
        open={Boolean(anchorEl)}
        onClick={handleClose}
        onClose={handleClose}
        aria-label={BreadcrumbConstants.MORE_MENU}
        variant='menu'
        hideBackdrop={true}
        MenuListProps={{
          'aria-labelledby': 'lock-button',
          role: 'listbox',
        }}
      >
        <StyledMenuItem
          onClick={() =>
            setShowSharePermissions((prev) => {
              setShowSettings(false);
              return !prev;
            })
          }
          disabled={disabledForInbuiltDashboard}
          id={`menu-item${generateRandomNumber()}`}
          inputprops={{
            'aria-label': BreadcrumbConstants.SHARE_DASHBOARD,
            'data-testid': 'menu-item',
          }}
          has_border='true'
        >
          <StyledShareIcon />
          {BreadcrumbConstants.SHARE_DASHBOARD}
        </StyledMenuItem>
        <StyledMenuItem
          onClick={() => openCustomDashboardEditor(true, true)}
          disabled={disabledForInbuiltDashboard}
          id={`menu-item${generateRandomNumber()}`}
          inputprops={{
            'aria-label': BreadcrumbConstants.EDIT_DASHBOARD,
            'data-testid': 'menu-item',
          }}
        >
          <StyledEditIcon />
          {BreadcrumbConstants.EDIT_DASHBOARD}
        </StyledMenuItem>
        <StyledMenuItem
          onClick={() => {
            pgAdmin.Browser.notifier.confirm(
              gettext('Delete dashboard'),
              gettext('Are you sure you want to delete this dashboard?'),
              function () {
                deleteCustomDashboard();
                return true;
              },
              function () {
                /* If user clicks No */ return true;
              }
            );
          }}
          disabled={disabledForInbuiltDashboard}
          id={`menu-item${generateRandomNumber()}`}
          inputprops={{
            'aria-label': BreadcrumbConstants.DELETE_DASHBOARD,
            'data-testid': 'menu-item',
          }}
        >
          <StyledDeleteIcon />
          {BreadcrumbConstants.DELETE_DASHBOARD}
        </StyledMenuItem>
        <StyledMenuItem
          onClick={() => exportCustomDashboard()}
          disabled={disabledForInbuiltDashboard}
          id={`menu-item${generateRandomNumber()}`}
          inputprops={{
            'aria-label': BreadcrumbConstants.EXPORT_DASHBOARD,
            'data-testid': 'menu-item',
          }}
          has_border='true'
        >
          <StyledExportIcon />
          {BreadcrumbConstants.EXPORT_DASHBOARD}
        </StyledMenuItem>
        <StyledMenuItem
          onClick={() => openCustomDashboardEditor(true, false)}
          id={`menu-item${generateRandomNumber()}`}
          inputprops={{
            'aria-label': BreadcrumbConstants.CREATE_DASHBOARD,
            'data-testid': 'menu-item',
          }}
        >
          <StyledAddIcon />
          {getMenuLabel(BreadcrumbConstants.CREATE_DASHBOARD, level)}
        </StyledMenuItem>
        <StyledMenuItem
          onClick={() => {
            pgAdmin.Browser.notifier.showModal(
              gettext('Import Custom Dashboard'),
              (closeDialog) => {
                return (
                  <ImportCustomDashboard
                    closeDialog={closeDialog}
                    url={url_for(
                      BreadcrumbConstants.IMPORT_CUSTOM_DASHBOARD_URL
                    )}
                    refreshDashboard={() =>
                      fetchDashboardContent(currentSelection?.url, false)
                    }
                  />
                );
              },
              {
                isFullScreen: true,
                isResizeable: true,
                showFullScreen: true,
                isFullWidth: true,
                dialogWidth: pgAdmin.Browser.stdW.md,
                dialogHeight: pgAdmin.Browser.stdH.md,
                showBackdrop: false,
              }
            );
          }}
          id={`menu-item${generateRandomNumber()}`}
          inputprops={{
            'aria-label': BreadcrumbConstants.IMPORT_DASHBOARD,
            'data-testid': 'menu-item',
          }}
        >
          <StyledImportIcon />
          {BreadcrumbConstants.IMPORT_DASHBOARD}
        </StyledMenuItem>
      </Menu>
    </>
  );
};

SettingsSection.propTypes = {
  setShowSettings: PropTypes.func.isRequired,
  setShowSharePermissions: PropTypes.func.isRequired,
  disabledForInbuiltDashboard: PropTypes.bool.isRequired,
  openCustomDashboardEditor: PropTypes.func.isRequired,
  level: PropTypes.number.isRequired,
  currentSelection: PropTypes.object.isRequired,
  deleteCustomDashboard: PropTypes.func.isRequired,
  fetchDashboardContent: PropTypes.func.isRequired,
};

export default withPEMRoleCheck(
  'pem_manage_dashboard',
  'Manage dashboard panel',
  SettingsSection,
  false
);

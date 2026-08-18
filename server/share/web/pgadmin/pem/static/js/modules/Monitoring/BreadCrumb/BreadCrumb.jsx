///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState, useEffect } from 'react';
import HomeIcon from '@mui/icons-material/Home';
import PropTypes from 'prop-types';
import { usePgAdmin } from 'sources/PgAdminProvider';
import getApiInstance from 'sources/api_instance';
import url_for from 'sources/url_for';
import SettingsSection from 'pem/modules/Monitoring/dashboards/settings/SettingsSection';
import { withPEMRoleCheckPromise } from 'sources/pem/helpers/withPEMRoleCheckPromise';
import BreadCrumbSection from 'pem/modules/Monitoring/BreadCrumb/BreadCrumbSection';
import {
  StyledHomeButton,
  StyledOutlinedInput,
  StyledIconButton,
  StyledMonitoringGrid,
  StyledPrimaryButton,
  StyledDefaultButton,
  StyledSettingsGroup,
} from 'pem/modules/Monitoring/Common/StyledComponents';
import SettingsIcon from '@mui/icons-material/Settings';
import CloseSharpIcon from '@mui/icons-material/CloseSharp';
import SaveSharpIcon from '@mui/icons-material/SaveSharp';
import SettingsRoundedIcon from '@mui/icons-material/SettingsRounded';
import gettext from 'sources/gettext';
import { handleAPIError } from 'pem/common/utils';
import {
  getSectionLabel,
  findParentHierarchy,
  getParentDetails,
  getDashboardURL,
  getPanelTitle,
} from 'pem/modules/Monitoring/Common/utils';
import {
  initDashboardData,
  BreadcrumbConstants,
} from 'pem/modules/Monitoring/Common/constants';

const BreadCrumb = ({
  currentSelection,
  setCurrentSelection,
  menuContent,
  showDashboardEditor,
  deleteCustomDashboard,
  setShowSharePermissions,
  customDashboardSchema,
  setCustomDashboardSchema,
  openCustomDashboardEditor,
  disableSettings,
  disabledForInbuiltDashboard,
  setShowSettings,
  fetchDashboardContent,
  panelId,
}) => {
  const [hasAccess, setHasAccess] = useState(null);

  const api = getApiInstance();
  const pgAdmin = usePgAdmin();

  useEffect(() => {
    withPEMRoleCheckPromise('pem_manage_dashboard')
      .then((hasAccess) => {
        setHasAccess(hasAccess);
      })
      .catch((err) => {
        console.error('Access denied or API issue', err);
        setHasAccess(false);
      });
  }, []);

  useEffect(() => {
    if (panelId && menuContent?.length > 0) {
      const handler = pgAdmin.Browser.getDockerHandler?.(panelId);
      handler?.docker.setTitle(
        panelId,
        getPanelTitle(menuContent, currentSelection)
      );
    }
  }, [menuContent]);

  const redirectToDashboard = (res) => {
    const url = getDashboardURL(res?.data?.data?.id, currentSelection);
    setCurrentSelection({
      label: customDashboardSchema.name,
      url: url,
      id: res?.data?.data?.id,
      parent_id: getParentDetails(
        customDashboardSchema.level,
        'dashboard',
        currentSelection?.parent_id?.aid,
        currentSelection?.parent_id?.sid,
        currentSelection?.parent_id?.database
      ),
      object_type: 'dashboard',
      level: customDashboardSchema.level,
      section_label: getSectionLabel(
        BreadcrumbConstants.CUSTOM_DASHBOARDS,
        customDashboardSchema.level
      ),
    });
    setTimeout(() => openCustomDashboardEditor(false, false), 200);
  };

  const saveDashboard = () => {
    if (
      menuContent[menuContent.length - 1].find(
        (option) =>
          option.label.toLowerCase() ===
          customDashboardSchema.name.toLowerCase()
      )
    ) {
      pgAdmin.Browser.notifier.error(
        gettext('Dashboard with the same name already exists.'),
        3000
      );
      return;
    }
    api
      .post(
        url_for(BreadcrumbConstants.CREATE_DASHBOARD_URL),
        customDashboardSchema
      )
      .then(redirectToDashboard)
      .catch((err) => handleAPIError(err));
  };

  const updateDashboard = () => {
    api
      .put(
        url_for(BreadcrumbConstants.UPDATE_CUSTOM_DASHBOARD_URL),
        customDashboardSchema
      )
      .then(redirectToDashboard)
      .catch((err) => handleAPIError(err));
  };
  return (
    <StyledMonitoringGrid
      container
      direction='row'
      alignItems='stretch'
      justifyContent='space-between'
      sx={{ width: '100%' }}
    >
      <div className='breadcrumb-section'>
        <StyledHomeButton
          variant='text'
          aria-haspopup='listbox'
          aria-controls='home-dashboard-button'
          aria-label={BreadcrumbConstants.GLOBAL_OVERVIEW_DASHBOARD}
          disabled={showDashboardEditor}
          onClick={() => {
            setCurrentSelection(initDashboardData);
          }}
        >
          <HomeIcon />
        </StyledHomeButton>
        {menuContent.map((menu, id) =>
          id + 1 === menuContent?.length && showDashboardEditor ? (
            <StyledOutlinedInput
              key={id}
              variant='outlined'
              id='outlined-basic'
              data-testid='custom-dashboard-name-input'
              value={customDashboardSchema?.name}
              onChange={(e) =>
                setCustomDashboardSchema((prev) => ({
                  ...prev,
                  name: e.target.value,
                }))
              }
              aria-label={gettext('Enter custom dashboard name')}
            />
          ) : (
            <BreadCrumbSection
              options={menu}
              key={id}
              index={id}
              level={menuContent?.length}
              parentHierarchy={findParentHierarchy(
                menuContent,
                currentSelection
              )}
              currentSelection={currentSelection}
              setCurrentSelection={setCurrentSelection}
              showDashboardEditor={showDashboardEditor}
              deleteCustomDashboard={deleteCustomDashboard}
            />
          )
        )}
        {showDashboardEditor && (
          <StyledIconButton
            variant='text'
            aria-haspopup='listbox'
            aria-controls='settings-menu'
            aria-label={gettext('Dashboard Share Permissions Button')}
            onClick={() => setShowSharePermissions((prev) => !prev)}
          >
            <SettingsIcon />
          </StyledIconButton>
        )}
      </div>
      {showDashboardEditor ? (
        <div>
          <StyledDefaultButton
            startIcon={<CloseSharpIcon />}
            onClick={() => openCustomDashboardEditor(false, false)}
            aria-label={BreadcrumbConstants.CANCEL_BUTTON}
          >
            {BreadcrumbConstants.CANCEL}
          </StyledDefaultButton>
          <StyledPrimaryButton
            startIcon={<SaveSharpIcon />}
            disabled={
              !customDashboardSchema?.design_layout.some(
                (section) => section.charts.length > 0
              )
            }
            aria-label={BreadcrumbConstants.SAVE_BUTTON}
            onClick={
              customDashboardSchema.editMode ? updateDashboard : saveDashboard
            }
          >
            {BreadcrumbConstants.SAVE}
          </StyledPrimaryButton>
        </div>
      ) : (
        <StyledSettingsGroup>
          <StyledIconButton
            variant='text'
            aria-haspopup='listbox'
            aria-controls='settings-menu'
            aria-label={gettext('Breadcrumb Settings Button')}
            disabled={disableSettings}
            onClick={() =>
              setShowSettings((prev) => {
                setShowSharePermissions(false);
                return !prev;
              })
            }
          >
            <SettingsRoundedIcon />
          </StyledIconButton>
          {hasAccess && (
            <SettingsSection
              setShowSettings={setShowSettings}
              setShowSharePermissions={setShowSharePermissions}
              disabledForInbuiltDashboard={disabledForInbuiltDashboard}
              level={menuContent?.length || 1}
              currentSelection={currentSelection}
              deleteCustomDashboard={deleteCustomDashboard}
              fetchDashboardContent={fetchDashboardContent}
              openCustomDashboardEditor={openCustomDashboardEditor}
            />
          )}
        </StyledSettingsGroup>
      )}
    </StyledMonitoringGrid>
  );
};

BreadCrumb.displayName = 'BreadCrumb';
BreadCrumb.propTypes = {
  currentSelection: PropTypes.object.isRequired,
  setCurrentSelection: PropTypes.func.isRequired,
  menuContent: PropTypes.array.isRequired,
  showDashboardEditor: PropTypes.bool.isRequired,
  deleteCustomDashboard: PropTypes.func.isRequired,
  setShowSharePermissions: PropTypes.func.isRequired,
  customDashboardSchema: PropTypes.object.isRequired,
  setCustomDashboardSchema: PropTypes.func.isRequired,
  openCustomDashboardEditor: PropTypes.func.isRequired,
  disableSettings: PropTypes.bool.isRequired,
  disabledForInbuiltDashboard: PropTypes.bool.isRequired,
  setShowSettings: PropTypes.func.isRequired,
  fetchDashboardContent: PropTypes.func.isRequired,
  panelId: PropTypes.string,
};

export default BreadCrumb;

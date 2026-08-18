///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState, useEffect, useRef, useCallback } from 'react';
import PropTypes from 'prop-types';

import { useTheme } from '@mui/material/styles';
import { isEqual } from 'lodash';
import { usePgAdmin } from 'sources/PgAdminProvider';
import getApiInstance from 'sources/api_instance';
import gettext from 'sources/gettext';
import ChartSection from 'pem/modules/Monitoring/charts/ChartSection';
import BreadCrumb from 'pem/modules/Monitoring/BreadCrumb/BreadCrumb';
import InfoTileComponent from 'pem/modules/info_tile_component/Component';
import DashboardConfigurations from 'pem/modules/Monitoring/dashboards/configuration/DashboardConfigurations';
import DashboardSharePermissions from 'pem/modules/Monitoring/dashboards/permissions/DashboardSharePermissions';
import CreateDashboardPanel from 'pem/modules/Monitoring/dashboards/customisation/Component';
import ChartDialog from 'pem/modules/Monitoring/dashboards/customisation/ChartDialog';
import Loader from 'sources/components/Loader';
import {
  hasLineChartInDashboardContent,
  structureData,
  getInitCustomDashboardSchema,
  generateCurrentDashboardSchema,
} from 'pem/modules/Monitoring/Common/utils';
import { handleError, handleAPIError } from 'pem/common/utils';
import {
  initDashboardData,
  BreadcrumbConstants,
  NODE_LEVEL_MAP,
} from 'pem/modules/Monitoring/Common/constants';
import url_for from 'sources/url_for';
import { DashboardSettingContext } from './dashboards/configuration/context';
import { useApplicationState } from 'top/settings/static/ApplicationStateProvider';

const MAX_CONCURRENT_REQUESTS = 4;
const DELAY_BETWEEN_BATCHES = 10;

const MonitoringComponent = ({
  details = {},
  panelId = '',
  trans_id = null,
}) => {
  const [showSettings, setShowSettings] = useState(false);
  const [disableSettings, setDisableSettings] = useState(true);
  const [showSharePermissions, setShowSharePermissions] = useState(false);
  const [disabledForInbuiltDashboard, setDisabledForInbuiltDashboard] =
    useState(true);
  const [showDashboardEditor, setShowDashboardEditor] = useState(false);
  const [customDashboardSchema, setCustomDashboardSchema] = useState(
    getInitCustomDashboardSchema(BreadcrumbConstants.GLOBAL)
  );

  const [chartList, setChartList] = useState([]);
  const [openChartModal, setOpenChartModal] = useState(false);
  const [modalTitle, setModalTitle] = useState({ title: '', id: 0 });
  const [filteredCharts, setFilteredCharts] = useState([]);
  const [selectedCharts, setSelectedCharts] = useState([]);

  const [currentSelection, setCurrentSelection] = useState(
    details?.url ? details : initDashboardData
  );
  const [dashboardData, setDashboardData] = useState({});
  const [menuContent, setMenuContent] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [linkedChartInfo, setLinkedChartInfo] = useState({
    linked: false,
    start: null,
    end: null,
    linked_span: null,
  });
  const { saveToolData, getToolContent } = useApplicationState();

  const api = getApiInstance();
  const pgAdmin = usePgAdmin();
  const theme = useTheme();

  const categoryColorMap = {};

  const selectedSectionHandler = (sectionTitle, sectionID) => {
    setModalTitle({ title: sectionTitle, id: sectionID });
    setOpenChartModal(true);
  };

  const editSection = (sectionTitle, sectionID) => {
    setFilteredCharts(chartList);

    const section = customDashboardSchema.design_layout.find(
      (sec) => sec.sec_id === sectionID
    );

    const selectedCharts =
      section?.charts
        ?.map((chart) =>
          chartList?.find((item) => item.cid === chart?.chart_id)
        )
        .filter(Boolean) || [];

    setSelectedCharts(selectedCharts);
    setModalTitle({ title: sectionTitle, id: sectionID });
    setOpenChartModal(true);
  };

  const openCustomDashboardEditor = (
    openDashboard = true,
    editMode = false
  ) => {
    const level =
      NODE_LEVEL_MAP[menuContent?.length || BreadcrumbConstants.GLOBAL];
    setCustomDashboardSchema(
      editMode
        ? generateCurrentDashboardSchema(dashboardData?.dashboard_content)
        : getInitCustomDashboardSchema(level)
    );
    setShowSettings(false);
    setShowSharePermissions(false);
    setShowDashboardEditor(openDashboard);
    openDashboard && getChartList(level);
  };

  useEffect(() => {
    const fetchData = async () => {
      const res = await getToolContent(trans_id);
      if (res?.data) setCurrentSelection(res.data);
    };
    if (trans_id) fetchData();
  }, []);

  const fetchDashboardContent = useCallback(
    (url, refreshCharts = true) => {
      setIsLoading(true);
      api
        .get(url)
        .then((res) => {
          const newDashboardData = res?.data?.data;
          if (!isEqual(newDashboardData, dashboardData)) {
            if (refreshCharts) {
              setDisableSettings(
                !hasLineChartInDashboardContent(
                  newDashboardData?.dashboard_content?.content
                )
              );
              setDashboardData(newDashboardData);
              setLinkedChartInfo({
                ...(newDashboardData?.info?.settings || { linked: false }),
              });
            }
            setMenuContent(structureData(newDashboardData?.menu_content));
          }
        })
        .catch((errorResponse) => {
          handleError(errorResponse);
        })
        .finally(() => {
          setIsLoading(false);
        });
    },
    [dashboardData]
  );

  useEffect(() => {
    if (trans_id) saveToolData('dashboard', null, trans_id, currentSelection);
    fetchDashboardContent(currentSelection?.url);
    setShowSettings(false);
    setShowSharePermissions(false);

    setDisabledForInbuiltDashboard(
      !['CUSTOM', 'OPS'].some((keyword) =>
        currentSelection?.section_label?.includes(keyword)
      )
    );
  }, [currentSelection]);

  const activePromises = useRef(0);
  const pendingRequests = useRef([]);

  const executeRequest = async (request) => {
    activePromises.current++;
    try {
      await request();
    } catch (err) {
      console.error('Error in request:', err);
    }
    activePromises.current--;
    processQueue();
  };

  const processQueue = () => {
    if (
      pendingRequests.current.length > 0 &&
      activePromises.current < MAX_CONCURRENT_REQUESTS
    ) {
      const nextRequest = pendingRequests.current.shift();
      executeRequest(nextRequest);
    }
  };

  const addToQueue = useCallback(
    (fetchFunction, delay = DELAY_BETWEEN_BATCHES) => {
      pendingRequests.current.push(fetchFunction);
      setTimeout(() => processQueue(), delay);
    },
    []
  );

  const deleteCustomDashboard = (id = currentSelection.id) => {
    api
      .post(
        url_for(BreadcrumbConstants.DELETE_CUSTOM_DASHBOARD_URL, {
          dashboard_id: id,
        })
      )
      .then(() => {
        setCurrentSelection(
          menuContent[menuContent.length - 1].find((item) => item.default)
        );
        pgAdmin.Browser.notifier.success(
          gettext('Dashboard deleted successfully.')
        );
      })
      .catch((err) => handleAPIError(err));
  };

  const getChartList = (level) => {
    api
      .get(url_for(BreadcrumbConstants.CHART_LIST_URL, { level }))
      .then((res) => {
        let colorIndex = 0;
        const chartDataWithColors = res?.data.map((chart) => {
          if (!categoryColorMap[chart.category]) {
            categoryColorMap[chart.category] =
              theme.otherVars.customDashboard.categoryChipColors[
                colorIndex %
                  theme.otherVars.customDashboard.categoryChipColors.length
              ];
            colorIndex++;
          }
          return { ...chart, color: categoryColorMap[chart.category] };
        });
        setChartList(chartDataWithColors);
        setFilteredCharts(chartDataWithColors);
      })
      .catch((err) => handleAPIError(err));
  };

  const setLinkedZoomRange = (_start, _end) => {
    if (!linkedChartInfo.linked) return;
    setLinkedChartInfo({ ...linkedChartInfo, start: _start, end: _end });
  };

  const setDashboardSettings = (_data) => {
    setLinkedChartInfo(_data);
  };

  return (
    <>
      <DashboardSettingContext.Provider
        value={{
          setLinkedZoomRange,
          linkedChartInfo,
          setDashboardSettings,
        }}
      >
        <BreadCrumb
          currentSelection={currentSelection}
          setCurrentSelection={setCurrentSelection}
          menuContent={menuContent}
          showDashboardEditor={showDashboardEditor}
          deleteCustomDashboard={deleteCustomDashboard}
          setShowSharePermissions={setShowSharePermissions}
          customDashboardSchema={customDashboardSchema}
          setCustomDashboardSchema={setCustomDashboardSchema}
          openCustomDashboardEditor={openCustomDashboardEditor}
          disableSettings={disableSettings}
          disabledForInbuiltDashboard={disabledForInbuiltDashboard}
          setDisabledForInbuiltDashboard={setDisabledForInbuiltDashboard}
          setShowSettings={setShowSettings}
          fetchDashboardContent={fetchDashboardContent}
          panelId={panelId}
        />
        {showSettings && (
          <DashboardConfigurations
            setShowSettings={setShowSettings}
            dashboardSettings={dashboardData?.info}
            refreshDashboardContent={() =>
              fetchDashboardContent(currentSelection?.url)
            }
          />
        )}
        {showSharePermissions && (
          <DashboardSharePermissions
            currentSelection={currentSelection}
            setShowSharePermissions={setShowSharePermissions}
            refreshDashboardContent={() =>
              fetchDashboardContent(currentSelection?.url)
            }
            showDashboardEditor={showDashboardEditor}
            customDashboardSchema={customDashboardSchema}
            setCustomDashboardSchema={setCustomDashboardSchema}
          />
        )}
        <InfoTileComponent infoTileData={dashboardData?.info} />
        {isLoading && <Loader message={BreadcrumbConstants.LOADING_MESSAGE} />}
        {showDashboardEditor ? (
          <CreateDashboardPanel
            designLayout={customDashboardSchema.design_layout}
            setCustomDashboardSchema={setCustomDashboardSchema}
            chartList={chartList}
            selectedSectionHandler={selectedSectionHandler}
            editSection={editSection}
          />
        ) : (
          <ChartSection
            dashboardData={dashboardData}
            addToQueue={addToQueue}
            setCurrentSelection={setCurrentSelection}
          />
        )}
        <ChartDialog
          openChartModal={openChartModal}
          modalTitle={modalTitle}
          filteredCharts={filteredCharts}
          selectedCharts={selectedCharts}
          setOpenChartModal={setOpenChartModal}
          setFilteredCharts={setFilteredCharts}
          setSelectedCharts={setSelectedCharts}
          chartList={chartList}
          setCustomDashboardSchema={setCustomDashboardSchema}
        />
      </DashboardSettingContext.Provider>
    </>
  );
};

MonitoringComponent.propTypes = {
  details: PropTypes.object,
  panelId: PropTypes.string,
  trans_id: PropTypes.oneOfType([PropTypes.object, PropTypes.number]),
};

export default MonitoringComponent;

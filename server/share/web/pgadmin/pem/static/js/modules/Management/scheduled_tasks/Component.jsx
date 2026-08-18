///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { Suspense, useEffect, useState } from 'react';
import Grid from '@mui/material/Grid';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import PropTypes from 'prop-types';
import ErrorBoundary from 'sources/helpers/ErrorBoundary';
import withStandardTabInfo from 'sources/helpers/withStandardTabInfo';
import PanelHeader from './common/components/PanelHeader';
import TabTable from './common/components/TabTable';
import { StyledBox } from 'pem/common/StyledComponents';
import Loader from 'sources/components/Loader';
import getApiInstance from 'sources/api_instance';
import {
  TabsSection,
  DefaultTabContainer,
  InformationIcon,
} from './common/StyledComponents';
import {
  allyProps,
  getHistoryTableUrl,
  getTasksTableUrl,
  getTargetData,
} from './common/utils';
import {
  getHistoryTableColumns,
  getTaskTableColumns,
} from './common/components/TableColumns';
import { SCHEDULED_TASKS_CONSTANTS } from './common/constants';
import { PEM_PANELS } from 'pem/Panels/constants';

const ScheduledTasksPanel = ({ nodeData, treeNodeInfo }) => {
  const [target, setTarget] = useState({});
  const [tasksData, setTasksData] = useState([]);
  const [showSystemTasks, setShowSystemTasks] = useState(false);
  const [nestedTableData, setNestedTableData] = useState({});
  const [errMsg, setErrMsg] = useState('');
  const [selectedTab, setSelectedTab] = useState(0);
  const [loadingData, setLoadingData] = useState(false);
  const [pages, setPages] = useState([1, 1]);
  const [totalRows, setTotalRows] = useState(0);
  const [searchQuery, setSearchQuery] = useState('');
  const api = getApiInstance();

  const tempURL =
    selectedTab === 0
      ? getTasksTableUrl(target, showSystemTasks)
      : getHistoryTableUrl(target, showSystemTasks);

  useEffect(() => {
    const tempTarget = getTargetData(nodeData, treeNodeInfo);
    if (tempTarget.targetLevel === -1) {
      setErrMsg(SCHEDULED_TASKS_CONSTANTS.INVALID_NODE_SELECTED);
    } else if (tempTarget.targetLevel === 50) {
      setErrMsg(SCHEDULED_TASKS_CONSTANTS.NO_NODE_SELECTED);
    } else {
      setErrMsg('');
      setTarget(tempTarget);
    }
  }, [nodeData, treeNodeInfo]);

  useEffect(() => {
    if (target && tempURL) {
      fetchScheduledTasksData();
    }
  }, [target, selectedTab, showSystemTasks, pages]);

  const fetchScheduledTasksData = (_page = null) => {
    setLoadingData(true);
    const formattedSearch = searchQuery
      .split(/\s+/)
      .filter(Boolean)
      .join(' & ');
    api
      .get(
        `${tempURL}?page=${_page || pages[selectedTab]}${
          searchQuery ? `&search_query=${formattedSearch}` : ''
        }`
      )
      .then((res) => {
        setTasksData(res.data.rows);
        setTotalRows(res.data.total_count);
        setLoadingData(false);
      })
      .catch((err) => {
        console.error('Failed to load scheduled tasks:', err);
        setTasksData([]);
        setErrMsg(SCHEDULED_TASKS_CONSTANTS.API_ERROR_MESSAGE);
        setLoadingData(false);
      });
  };

  const handleToggleChange = () => {
    setShowSystemTasks((prev) => !prev);
    setSearchQuery('');
  };

  const handleTabChange = (newValue) => {
    setTasksData([]);
    setSelectedTab(newValue);
    setSearchQuery('');
  };

  const setPage = (page) => {
    const _pages = [...pages];
    _pages[selectedTab] = page;
    setPages(_pages);
  };
  return (
    <StyledBox>
      <ErrorBoundary>
        <Suspense fallback={<div>{SCHEDULED_TASKS_CONSTANTS.LOADING}</div>}>
          <PanelHeader />
          <Grid size="grow">
            <TabsSection>
              <Tabs
                value={selectedTab}
                onChange={(_, val) => handleTabChange(val)}
              >
                {[
                  { label: SCHEDULED_TASKS_CONSTANTS.TASKS, index: 0 },
                  { label: SCHEDULED_TASKS_CONSTANTS.HISTORY, index: 1 },
                ].map(({ label, index }) => (
                  <Tab key={index} label={label} {...allyProps(index)} />
                ))}
              </Tabs>
            </TabsSection>
            {loadingData && (
              <Loader message={SCHEDULED_TASKS_CONSTANTS.LOADING} />
            )}
            {errMsg ? (
              <DefaultTabContainer>
                <InformationIcon /> {errMsg}
              </DefaultTabContainer>
            ) : (
              <>
                {[0, 1].map((index) => (
                  <TabTable
                    key={index}
                    index={index}
                    columns={
                      index === 0
                        ? getTaskTableColumns(
                          target,
                          setNestedTableData,
                          fetchScheduledTasksData
                        )
                        : getHistoryTableColumns(setNestedTableData)
                    }
                    data={tasksData}
                    fetchData={fetchScheduledTasksData}
                    selectedTab={selectedTab}
                    nestedTableData={nestedTableData}
                    showSystemTasks={showSystemTasks}
                    handleToggleChange={handleToggleChange}
                    page={pages[index]}
                    setPage={setPage}
                    totalRows={totalRows}
                    searchQuery={searchQuery}
                    setSearchQuery={setSearchQuery}
                  />
                ))}
              </>
            )}
          </Grid>
        </Suspense>
      </ErrorBoundary>
    </StyledBox>
  );
};

ScheduledTasksPanel.propTypes = {
  treeNodeInfo: PropTypes.object,
  nodeData: PropTypes.object,
};

export default withStandardTabInfo(
  ScheduledTasksPanel,
  PEM_PANELS.SCHEDULED_TASKS
);

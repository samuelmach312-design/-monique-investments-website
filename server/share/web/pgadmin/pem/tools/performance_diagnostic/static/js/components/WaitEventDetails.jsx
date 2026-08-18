///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState, useMemo, useEffect } from 'react';
import { Box, Tab, Tabs } from '@mui/material';
import { styled } from '@mui/material/styles';
import PropTypes from 'prop-types';
import { InputSelectNonSearch, FormNote } from 'sources/components/FormComponents';
import gettext from 'sources/gettext';
import TabPanel from 'sources/components/TabPanel';
import PgTable from 'sources/components/PgTable';
import EmptyPanelMessage from 'sources/components/EmptyPanelMessage';
import {getColumns} from './eventColumns';

const Root = styled('div')(({theme}) => ({
  width: '100%',
  '&  .pgrt-header-row': {
    height: theme.spacing(9.3) + '!important',
  },
  '&  .Event-Details': {
    display: 'flex',
    padding: theme.spacing(1.25),
  },
  '&  .summaryDetails': {
    marginLeft: theme.spacing(1.25),
  },
}));

const queryWaitColumns = 'queryWaitColumns',
  queryCPUColumns = 'queryCPUColumns',
  userWaitColumns = 'userWaitColumns',
  userCPUColumns = 'userCPUColumns',
  sampleQueryColumns = 'sampleQueryColumns',
  sampleUserColumns = 'sampleUserColumns',
  sampleWaitsColumns = 'sampleWaitsColumns',
  sql = 'sql',
  users = 'users',
  waits = 'waits',
  eventSummary = {
    queryWaitColumns: gettext('Shows the users whose queries have used the most CPU time across all sessions over the selected time period.'),
    queryCPUColumns: gettext('Lists the queries across all the sessions for the selected time interval that have used the most CPU time.'),
    userWaitColumns: gettext('Shows the users whose queries have spent the longest time in wait states across all sessions over the selected time period.'),
    userCPUColumns: gettext('Shows the users whose queries have used the most CPU time across all sessions over the selected time period.')
  };


function EventTypeHeader({eventType, setEventType}) {
  return (<>
    <InputSelectNonSearch
      label={gettext('Event Type')}
      className='Dashboard-searchInput'
      value={eventType}
      onChange={(e) => {
        setEventType(e.currentTarget.value);
      }}
      options={[
        {'label': gettext('Top Queries by wait events'), 'value': queryWaitColumns},
        {'label': gettext('Top Queries by CPU usage'), 'value': queryCPUColumns},
        {'label': gettext('Top Users by wait events'), 'value': userWaitColumns},
        {'label': gettext('Top Users by CPU usage'), 'value': userCPUColumns},
      ]}
    ></InputSelectNonSearch>
    <FormNote text={eventSummary[eventType]} className='summaryDetails'/></>
  );
}
EventTypeHeader.propTypes = {
  eventType: PropTypes.string,
  setEventType: PropTypes.func,
};


function SampleEventTypeHeader({eventType, setEventType, setParentSampleEventType}) {
  return (
    <InputSelectNonSearch
      label={gettext('Event Type')}
      className='Dashboard-searchInput'
      value={eventType}
      onChange={(e) => {
        setEventType(e.currentTarget.value);
        setParentSampleEventType(e.currentTarget.value);
      }}
      options={[
        {'label': gettext('Queries'), 'value': sql},
        {'label': gettext('Users'), 'value': users},
        {'label': gettext('Waits'), 'value': waits},
      ]}
      labelGridBasis={6}
      controlGridBasis={3}
    ></InputSelectNonSearch>
  );
}
SampleEventTypeHeader.propTypes = {
  eventType: PropTypes.string,
  setEventType: PropTypes.func,
  setParentSampleEventType: PropTypes.func,
};

export default function WaitEventDetailsComponent({data, sampleReportData, setParentSampleEventType, getSampleSelection, chartColors, samTime, transId}) {
  let mainTabs = [gettext('Summary'), gettext('Sample Selection')];
  const [sampleTime, setSampleTime] = useState(samTime);
  const [cols, setCols] = useState(getColumns(chartColors, sampleTime, transId));
  const [mainTabVal, setMainTabVal] = useState(0);
  const [eventType, setEventType] = useState(queryWaitColumns);
  const [columType, setColumType] = useState(cols[queryWaitColumns]);
  const [sampleColumnType, setSampleColumnType] = useState(queryWaitColumns);
  const [sampleEventType, setSampleEventType] = useState(sql);

  const transformData = function(data) {
    if (data) {
      return data.map((val) => {
        let _data = val;
        if (_.isArray(val['load_by_waits'])) {

          _data['wait_event_type'] = val['load_by_waits'][0]['wait_event_type'];
          _data['count'] = val['load_by_waits'][0]['count'];
        }

        return _data;
      });
    }
    return data;
  };

  const transformReportData = function(data) {
    if (data) {
      return data.map((val) => {
        let _data = val;

        let total_samples = val['wait_event_count'] + val['cpu_count'];

        _data['wait_event_percent'] = ((
          val['wait_event_count'] / total_samples
        ) * 100).toFixed(2);

        _data['cpu_percent'] = ((
          val['cpu_count'] / (val['wait_event_count'] + val['cpu_count'])
        ) * 100).toFixed(2);

        if ('queries_count' in val) {
          _data['avg_wait_events_vs_cpu'] = (val['wait_event_count'] / val['queries_count']).toFixed(2) + ' / ' + (val['cpu_count'] / val['queries_count']).toFixed(2);
        }

        return _data;
      });
    }
    return data;
  };

  const mainTabChanged = (e, tabVal) => {
    setMainTabVal(tabVal);
  };

  useEffect(() => {
    setCols(getColumns(chartColors, sampleTime, transId));
    setSampleTime(samTime);
  }, [samTime]);

  useEffect(() => {
    getSampleSelection();
    setCols(getColumns(chartColors, sampleTime, transId));

    switch(sampleEventType) {
    case sql:
      setSampleColumnType(cols[sampleQueryColumns]);
      break;
    case users:
      setSampleColumnType(cols[sampleUserColumns]);
      break;
    case waits:
      setSampleColumnType(cols[sampleWaitsColumns]);
      break;
    }
  }, [sampleEventType]);

  const getSampleColumns = () => {
    let _cols = undefined;
    switch(sampleEventType) {
    case sql:
      _cols = cols[sampleQueryColumns];
      break;
    case users:
      _cols = cols[sampleUserColumns];
      break;
    case waits:
      _cols = cols[sampleWaitsColumns];
      break;
    }
    return _cols;
  };


  const getEventColumns = () => {
    let _cols = undefined;
    switch(eventType) {
    case queryWaitColumns:
      _cols = cols[queryWaitColumns];
      break;
    case queryCPUColumns:
      _cols = cols[queryCPUColumns];
      break;
    case userWaitColumns:
      _cols = cols[userWaitColumns];
      break;
    case userCPUColumns:
      _cols = cols[userCPUColumns];
      break;
    }
    return _cols;
  };


  useEffect(()=>{
    switch(eventType) {
    case queryWaitColumns:
      setColumType(cols[queryWaitColumns]);
      break;
    case queryCPUColumns:
      setColumType(cols[queryCPUColumns]);
      break;
    case userWaitColumns:
      setColumType(cols[userWaitColumns]);
      break;
    case userCPUColumns:
      setColumType(cols[userCPUColumns]);
      break;
    }
  },[eventType, samTime]);

  const filteredData = useMemo(()=>{
    let _data = [];
    setCols(getColumns(chartColors, sampleTime, transId));
    switch(eventType) {
    case queryCPUColumns:
      _data = ('top_queries_by_cpu_usage' in data) ? data['top_queries_by_cpu_usage'] : [];
      break;
    case queryWaitColumns:
      _data = ('top_queries_by_wait_events' in data) ? data['top_queries_by_wait_events'] : [];
      break;
    case userCPUColumns:
      _data = ('top_users_by_cpu_usage' in data) ? data['top_users_by_cpu_usage'] : [];
      break;
    case userWaitColumns:
      _data = ('top_users_by_wait_events' in data) ? data['top_users_by_wait_events'] : [];
      break;

    }
    return transformReportData(_data);
  }, [data, eventType, mainTabVal, sampleTime]);

  return (
    <Root key={sampleTime}>
      <Box>
        <Box>
          <Tabs value={mainTabVal} onChange={mainTabChanged}>
            {mainTabs.map((tabValue, i) => {
              return <Tab key={tabValue} label={tabValue} value={i}/>;
            })}
          </Tabs>
        </Box>
        <TabPanel value={mainTabVal} index={0}>
          {columType && data !== undefined ?  (<PgTable
            showSearch={false}
            className='Event-Details'
            caveTable={false}
            tableNoBorder={false}
            customHeader={<EventTypeHeader eventType={eventType} setEventType={setEventType}/>}
            columns={getEventColumns()}
            data={filteredData || []}
          ></PgTable>) : (
            <EmptyPanelMessage text={gettext('No wait event samples are available for the selected range.')}/>
          )
          }
        </TabPanel>
        <TabPanel value={mainTabVal} index={1}>
          {sampleColumnType && sampleTime !==0 ? (
            <div>{sampleTime &&
               <PgTable
                 showSearch={false}
                 caveTable={false}
                 tableNoBorder={false}
                 customHeader={<SampleEventTypeHeader eventType={sampleEventType} setEventType={setSampleEventType} setParentSampleEventType={setParentSampleEventType}/>}
                 columns={getSampleColumns()}
                 data={transformData(sampleReportData) || []}
               ></PgTable>}</div>
          ) : (
            <EmptyPanelMessage text={gettext('Please select the sample time from above chart.')}/>
          )}
        </TabPanel>
      </Box>
    </Root>
  );

}
WaitEventDetailsComponent.propTypes = {
  data: PropTypes.object,
  sampleReportData: PropTypes.array,
  setParentSampleEventType: PropTypes.func,
  getSampleSelection: PropTypes.func,
  chartColors: PropTypes.object,
  samTime: PropTypes.any,
  transId: PropTypes.number,
};

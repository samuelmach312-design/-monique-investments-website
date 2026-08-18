///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState, useEffect, useMemo } from 'react';
import { Box, Grid, FormLabel, Card, CardContent, useTheme } from '@mui/material';
import { styled } from '@mui/material/styles';
import KeyboardArrowUpIcon from '@mui/icons-material/KeyboardArrowUp';
import KeyboardArrowDownIcon from '@mui/icons-material/KeyboardArrowDown';
import PropTypes from 'prop-types';
import _ from 'lodash';
import * as DateFns from 'date-fns';
import url_for from 'sources/url_for';
import { FormNote, InputSelect } from 'sources/components/FormComponents';
import gettext from 'sources/gettext';
import getApiInstance from 'sources/api_instance';
import { DATA_POINT_SIZE, PieChart} from 'sources/chartjs';
import CodeMirror from 'sources/components/ReactCodeMirror';
import StackedBars from 'sources/components/PgChart/StackedBars';
import PgTable from 'sources/components/PgTable';
import { getLinearProgressCell, getQueryDashboardEventCell } from 'sources/components/PgReactTableStyled';
import { PgIconButton } from 'sources/components/Buttons';
import ChartContainer from '../../../../../../../pgadmin/dashboard/static/js/components/ChartContainer';
import LegendsComponent from './LegendsComponent';

// Number of top queries and top users are hardcoded to 15 at the moment.
// We could use configurable limits for top queries and users.
// const LIMIT = 15;
const MAX_POINTS = 40;

const waitEventSamples = [
  {
    accessorKey: 'event',
    header: gettext('Wait event'),
    enableSorting: true,
    enableResizing: true,
    enableFilters: true,
    minSize: 50,
    size: 50,
    cell: getQueryDashboardEventCell({}),
  },
  {
    accessorKey: 'sample_time',
    header: gettext('Sample time'),
    enableSorting: true,
    enableResizing: true,
    enableFilters: true,
    minSize: 50,
    size: 50,
  },
];

const waitEvents = [
  {
    accessorKey: 'event',
    header: gettext('Wait event'),
    enableSorting: true,
    enableResizing: true,
    enableFilters: true,
    minSize: 50,
    size: 50,
    cell: getQueryDashboardEventCell({typeIcon: false}),
  },
  {
    accessorKey: 'percentage',
    header: '%',
    enableSorting: true,
    enableResizing: true,
    enableFilters: true,
    minSize: 50,
    size: 50,
  },
  {
    accessorKey: 'percentile',
    header: '#',
    enableSorting: true,
    enableResizing: true,
    enableFilters: true,
    minSize: 50,
    size: 50,
    cell: getLinearProgressCell({})
  },
];


const StyledBox = styled(Box)(({theme}) => ({
  overflowY: 'scroll',
  display: 'flex',
  flexDirection: 'column',
  '& .QueryDashboard-container': {
    alignItems: 'flex-start',
    padding: theme.spacing(1.25),
    flexWrap: 'wrap',
    ...theme.mixins.panelBorder.bottom,
    '& .QueryDashboard-queryInfo': {
      margin: theme.spacing(0.5),
      marginTop: theme.spacing(1.25),
      border: '1px solid '+theme.otherVars.borderColor,
      boxShadow: 'none',
      '& .QueryDashboard-cardContent': {
        padding: theme.spacing(0.5, 1),
        display: 'block',
      },
    },
    '& .QueryDashboard-query': {
      margin: theme.spacing(0.5),
      marginTop: '0px',
      border: '1px solid '+theme.otherVars.borderColor,
      backgroundColor: theme.otherVars.editor.guttersBg,
      boxShadow: 'none',
      '& .QueryDashboard-cardContent': {
        padding:  theme.spacing(0.5, 1),
        display: 'block',
      },
    },
    '& .QueryDashboard-sub-heading': {
      display: 'flex',
      width: '100%',
      padding: theme.spacing(0.5),
      paddingBottom: theme.spacing(1.25, 0.5) + ' !important',
      fontWeight: 'bold',
      ...theme.mixins.panelBorder.bottom,
    },
    '& .QueryDashboard-label': {
      fontWeight: 'bold',
    },
    '& .QueryDashboard-displayFlex': {
      display: 'flex',
      width: '50%',
      '& .QueryDashboard-spanLabel': {
        alignSelf: 'center',
        minWidth: '6%',
        whiteSpace: 'nowrap',
        '& .QueryDashboard-axisSelectCtrl': {
          minWidth: theme.spacing(8),
          marginTop: theme.spacing(0.25),
        },
        '& .QueryDashboard-selectCtrl': {
          minWidth: theme.spacing(8),
        },
      },
    },
  },
  '& .QueryDashboard-graphContainer': {
    padding: theme.spacing(1),
    flexGrow: 1,
  },
  '& .SQL-textArea': {
    height: '100% !important',
    width: '100% !important',
    background: theme.palette.grey[400],
    minHeight: '100%',
    minWidth: '100%',
    overflowY: 'auto',
    maxHeight: theme.spacing(12.5),
  },
  '& .SQL-textAreaExpand': {
    height: 'auto !important',
    width: '100% !important',
    background: theme.palette.grey[400],
    overflowY: 'auto',
  },
  '& .Waitevent-subheading': {
    paddingTop: theme.spacing(1.25),
  },
  '& .expandIcon': {
    margin: 'auto',
    height: theme.spacing(2.25),
  },
  '& .querySession': {
    display: 'inline-flex',
  },
  '& .pie-chart': {
    width: theme.spacing(62.5),
  },

}));

export default function QueryDashboardComponent({ pgAdmin, params }) {
  const api = getApiInstance();
  const [queryData, setQueryData] = useState('');
  const [sessionData, setSessionData] = useState('');
  const [sessionQueryData, setSessionQueryData] = useState([]);
  const reportTime = params.report_time;
  const [barData, setBarData] = useState({ datasets: [], refreshRate: 5, timeline: []});
  const [pieData, setPieData] = useState({ datasets: [], refreshRate: 5, timeline: []});
  const [waitSummary, setWaitSummary] = useState([]);
  const [waitSamples, setWaitSamples] = useState([]);
  const [expanded, setExpanded] = useState(false);
  const [legend, setLegend] = useState({});
  const [activeLegend, setActiveLegend] = useState({});
  const theme = useTheme();


  const optionsZoom = useMemo(()=>({
    labelY: gettext('# wait events types'),
  }));


  const [totalWaitEvents, setTotalWaitEvents] = useState({'samples': [],
    'event_types': {},
    'colors': {},
  });

  useEffect(() => {
    let _url = url_for('performance_diagnostic.query_details_by_session', {
      'transid': params.trans_id,
      'query_id': params.query_id,
      'sample_time': params.sample_time,
    });


    api.get(_url).then((res)=>{
      setQueryData(res.data.query);
      setSessionData(res.data.query_sessions);
      setSessionQueryData(res.data.query_sessions?.[0]);
    }).catch((err)=>{
      pgAdmin.Browser.notifier.error(err);
    });
  }, [reportTime]);


  const generate_event_samples = (_data) => {

    let tableData = [];

    _.each(_data.samples, (_sample) => {
      tableData.push({
        'color': _data.colors[_sample.wait_event_types],
        'sample_time': DateFns.format(_sample.sample_time, 'yyyy-MM-dd HH:mm:ss'),
        'type': _sample.wait_event_types,
        'event': _sample.wait_events,
      });
    });
    return tableData;
  };

  const generate_event_summary = (_data) => {

    let events = [],
      total = _data.samples.length,
      max_val = 0;

    _.each(_data.event_types, (_type, _event_type) => {
      _.each(_type.events, (_val, _key) => {
        events.push({
          'event': _key, 'val': _val, 'type': _event_type,
          'color': _data.colors[_event_type],
        });
        if (_val > max_val) {
          max_val = _val;
        }
      });
    });

    _.each(_.sortBy(events, (_event)=>(-1 * _event.val)), (_event) => {
      Object.assign(
        _event, {
          'percentile': ((_event.val / max_val) * 100).toFixed(2),
          'percentage': ((_event.val / total) * 100).toFixed(2),
        }
      );
    });
    return events;
  };

  const generate_doughnut_dataset = (_dataset, _data, data, labels, colors) => {

    _.each(_dataset, (_val, _key) => {
      if (activeLegend[_key] != false) {
        data.push(_val.total);
        colors.push(_data.colors[_key]);
        labels.push(_key);
      }
    });

    return {
      datasets: [{
        data: data,
        backgroundColor: colors,
        labels: labels,
      }],
    };
  };

  const calculateGraphData = (_dataset, _colors) => {
    let event_types = {},
      timeline = [],
      initEventType = (_type, _curr) => {
        event_types[_type] = {
          data: [],
          curr: null,
          borderColor: _colors[_type],
          label: _type,
          hidden: false,
        };

        // Initialize the wait event type with zero values for the existing
        // timeline.
        _.each(timeline, (_time) => (
          _curr != _time && event_types[_type].data.push(0)
        ));
      },
      fillZero = (_curr) => {
        _.each(event_types, (_type) => {
          if (_type.curr != _curr) {
            _type.data.push(0);
            _type.curr = _curr;
          }
        });
        if (timeline.length && _curr !== timeline[timeline.length - 1]) {
          timeline.push(_curr);
        }
      },
      fillData = (_type, _curr) => {
        let event_type = event_types[_type];

        if (event_type.curr === _curr) {
          event_type.data[event_type.data.length - 1]++;
        } else {
          event_type.data.push(1);
        }
        event_type.curr = _curr;
      };

    if (_dataset.length === 0)
      return {datasets: [], timeline: [], options: []};

    let start = _dataset.length && _dataset[0].sample_time,
      end = _dataset.length && _dataset[_dataset.length - 1].sample_time,
      diff = (end - start) / (MAX_POINTS - 1),
      curr = Math.floor(start / 1000) * 1000;

    if (diff < 1000) {
      diff = 1000;
    }

    curr += diff;

    _.each(_dataset, (_sample) => {
      while (_sample.sample_time + diff > curr) {
        fillZero(curr);
        curr = curr + diff;
        timeline.push(curr);
      }
      if (!(_sample.wait_event_types in event_types)) {
        initEventType(_sample.wait_event_types, curr);
      }
      fillData(_sample.wait_event_types, curr);
    });
    fillZero(curr);

    let _timeline = [];
    timeline.forEach((t)=>{
      _timeline.push(DateFns.getHours(t) + ':' + DateFns.getMinutes(t) + ':' + DateFns.getSeconds(t));
    }) || [];

    let res = {
      datasets: [],
      timeline: _timeline,
      refreshRate: 5,
    };
    _.each(event_types, (_type) =>(res.datasets.push(_type)));

    return res;
  };

  const filterData = (data) => {
    if (data.datasets?.length > 0) {
      let _datasets = Object.values(data.datasets).filter(label => {
        if (activeLegend[label.label] == true) {
          return label;
        }
      });
      return {
        datasets: _datasets,
        timeline: data.timeline,
        refreshRate: 5,
      };
    }
    return data;
  };

  React.useEffect(() => {
    setBarData(filterData(calculateGraphData(Object.values(totalWaitEvents.samples), totalWaitEvents.colors)));
    setPieData(generate_doughnut_dataset(totalWaitEvents.event_types, totalWaitEvents, [], [], []));
  }, [activeLegend]);

  useEffect(() => {
    if (sessionQueryData.length == 0) return;
    let _url = url_for('performance_diagnostic.query_get_total_wait_events', {
      'transid': params.trans_id,
    });

    api.get(_url, {
      'params': {
        'sample_time': params.sample_time,
        'query_id': params.query_id,
        'session_id': sessionQueryData?.session_id,
      }}).then((res)=>{
      let _data = totalWaitEvents;
      _data.samples = (res && res.data && res.data.data.data) || [];
      _data.colors = (res && res.data && res.data.data.colors) || {};
      _.each(_data.samples, (_val) => {
        _val.sample_time = parseFloat(_val.sample_time);

        if (!(_val.wait_event_types in _data.event_types)) {
          _data.event_types[_val.wait_event_types] = {
            'events': {},
            total: 0,
          };
        }

        if (!(_val.wait_events in _data.event_types[_val.wait_event_types].events)) {
          _data.event_types[_val.wait_event_types].events[_val.wait_events] = 0;
        }
        _data.event_types[_val.wait_event_types].total++;
        _data.event_types[_val.wait_event_types].events[_val.wait_events]++;
      });

      setTotalWaitEvents(_data);
      setWaitSummary(generate_event_summary(_data));
      setWaitSamples(generate_event_samples(_data));
      setBarData(calculateGraphData(Object.values(_data.samples), _data.colors));
      setPieData(generate_doughnut_dataset(_data.event_types, _data, [], [], []));


      let _legends = {};
      Object.keys(_data.event_types).map(label => {
        _legends[label] = _data.colors[label];
      });
      setLegend(_legends);

    }).catch((err)=>{
      pgAdmin.Browser.notifier.error(err);
    });
  }, [reportTime, sessionQueryData]);


  return (
    <StyledBox>
      <Box className='QueryDashboard-container'>
        <Box className='QueryDashboard-sub-heading'>
          <FormNote controlProps={ {'raw': true} } text={gettext('Query information')} />
        </Box>
        {sessionQueryData && sessionData.length > 0 && <React.Fragment>
          <Card className='QueryDashboard-queryInfo' data-label="query-info">
            <CardContent className='QueryDashboard-cardContent'>
              <Grid container spacing={2}>
                <Grid size={4}>
                  <FormLabel className='QueryDashboard-label'>{gettext('Query ID:')} </FormLabel>{ params.query_id }
                </Grid>
                <Grid size={4}>
                  <FormLabel className='QueryDashboard-label'>{gettext('User:')} </FormLabel>{ sessionQueryData.username }
                </Grid>
                <Grid size={4}>
                  <FormLabel className='QueryDashboard-label'>{gettext('Database:')} </FormLabel>{ sessionQueryData.dbname }
                </Grid>
                <Grid size={4}>
                  <FormLabel className='QueryDashboard-label'>{gettext('Session ID:')}  </FormLabel>
                  <InputSelect value={sessionQueryData.session_id}
                    options={ Object.values(sessionData).map(session => {
                      return {'label': session.session_id, 'value': session.session_id};
                    })}
                    onChange={(val)=>{
                      setSessionQueryData(_.filter(sessionData, { 'session_id': val })[0]);
                    }}
                    className='querySession'
                    controlProps={{allowClear: false}}
                  ></InputSelect>
                </Grid>
                <Grid size={4}>
                  <FormLabel className='QueryDashboard-label'>{gettext('Execution count:')} </FormLabel>{sessionData?.length}
                </Grid>
                <Grid size={4}>
                  <FormLabel className='QueryDashboard-label'>{gettext('Sample time:')} </FormLabel>{  DateFns.format(params.sample_time, 'yyyy-MM-dd HH:mm:ss') }
                </Grid>
              </Grid>
            </CardContent>
          </Card>
          <Card className='QueryDashboard-query' data-label="query-info">
            {queryData && <Grid container sx={{padding: theme.spacing(0.5)}}>
              <CodeMirror
                value={queryData}
                className={expanded ? 'SQL-textArea'  : 'SQL-textAreaExpand'}
                readonly={true}
              />
              <div aria-label="' + gettext('Expand/Collapse') + '" tabIndex="0" className="expandIcon">
                <PgIconButton
                  size="xs"
                  icon={
                    expanded ? (
                      <KeyboardArrowDownIcon  />
                    ) : (
                      <KeyboardArrowUpIcon />
                    )
                  }
                  noBorder
                  onClick={() => {setExpanded((expanded) => !expanded);}}
                />
              </div>
            </Grid>}
          </Card> </React.Fragment>}
        <Grid size={{ md:6 }} sx={{padding: theme.spacing(0.5)}}>
          <ChartContainer class='sel-graph' id='sel-graph' title={gettext('Wait events type')}>
            {pieData && <div className='pie-chart'><PieChart data={pieData} dataPointSize={DATA_POINT_SIZE}
              options = {{
                plugins: {
                  tooltip: {
                    callbacks: {
                      label: function(context) {
                        let total = 0,
                          dataset = context.dataset,
                          index = context.dataIndex;

                        total = dataset.data.reduce((sum, value) => sum + value, 0);
                        return (`${dataset.labels[index]} : ${dataset.data[index]} [ ${total === 0 ? '0.00' : ((dataset.data[index] / total) * 100).toFixed(2)}% ]`);
                      },
                    },
                  },
                  legend: {
                    display:false
                  }
                },
              }}
            /></div>}
            <StackedBars data={barData} options={optionsZoom}/>
          </ChartContainer>
        </Grid>
        {legend && <LegendsComponent  legends={legend} onChange={setActiveLegend} />}
        <Box className='QueryDashboard-sub-heading'>
          <FormNote controlProps={ {'raw': true} } text={gettext('Wait events')} />
        </Box>
        <Grid size={{ md:6 }} sx={{padding: theme.spacing(0.5)}}>
          <div className='Waitevent-subheading'>Summary of the wait events <a href="https://www.postgresql.org/docs/current/monitoring-stats.html#WAIT-EVENT-TABLE" target="_new">{gettext('Read more')}</a></div>
          {waitSummary &&
               <PgTable
                 showSearch={false}
                 caveTable={false}
                 tableNoBorder={false}
                 columns={waitEvents}
                 data={waitSummary}
               ></PgTable>}
        </Grid>
        <Grid size={{ md:6 }} sx={{padding: theme.spacing(0.5), marginTop: theme.spacing(1.25)}}>
          <div>{gettext('Wait event samples')}</div>
          {waitSamples &&
               <PgTable
                 showSearch={false}
                 caveTable={false}
                 tableNoBorder={false}
                 columns={waitEventSamples}
                 data={waitSamples}
               ></PgTable>}
        </Grid>
      </Box>
    </StyledBox>
  );
}


QueryDashboardComponent.propTypes = {
  pgAdmin: PropTypes.object,
  params: PropTypes.object
};

///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import Breadcrumbs from '@mui/material/Breadcrumbs';
import NavigateNextIcon from '@mui/icons-material/NavigateNext';
import Typography from '@mui/material/Typography';

import { MONITORING_TARGET_LEVEL } from './constants';


const targetPath = (object) => {
  const GLOBAL = [['icon-server_group', 'system', 'Global']];
  switch (object.targetLevel) {
  case MONITORING_TARGET_LEVEL.GLOBAL:
    return GLOBAL;
  case MONITORING_TARGET_LEVEL.HOST:
    return [
      ['icon-agent', 'host', object.agent.label]
    ];
  case MONITORING_TARGET_LEVEL.DBSERVER:
    return [
      ['icon-server', 'server', object.server.label]
    ];
  case MONITORING_TARGET_LEVEL.DATABASE:
    return [
      ['icon-server', 'server', object.server.label],
      ['pg-icon-database', 'database', object.database.label]
    ];
  case MONITORING_TARGET_LEVEL.SCHEMA:
    return [
      ['icon-server', 'server', object.server.label],
      ['pg-icon-database', 'database', object.database.label],
      ['icon-schema', 'schema', object.schema.label]
    ];
  case MONITORING_TARGET_LEVEL.EXTENSION:
    return [
      ['icon-server', 'server', object.server.label],
      ['pg-icon-database', 'database', object.database.label],
      ['icon-extension', 'exension', object.extension.label]
    ];
  default:
    console.error('Unknown target level', object.targetLevel, object);
    return GLOBAL;
  }
};


let TargetInfoBreadcrum = (props) => {
  const path = targetPath(props.monitoringTarget);
  const targetInfoLabel = 'Monitoring target';

  return (
    <Breadcrumbs
      separator={<NavigateNextIcon fontSize="small" />}
      aria-label={targetInfoLabel}
      style={{ padding: '0.5em', backgroundColor: 'whitesmoke' }}
    >{
        path?.map((item) => {
          return (
            <Typography key={item[1]} color="text.primary">
              <i className={item[0]} style={{
                display: 'inline-block', height: '1.5rem', width: '1rem',
                marginRight: '8px'
              }}/>
              <b style={{padding: '0rem 0.25rem'}}>{item[2]}</b>
            </Typography>
          );
        })
      }</Breadcrumbs>
  );
};

TargetInfoBreadcrum.propTypes = {
  monitoringTarget: PropTypes.object
};

export default TargetInfoBreadcrum;

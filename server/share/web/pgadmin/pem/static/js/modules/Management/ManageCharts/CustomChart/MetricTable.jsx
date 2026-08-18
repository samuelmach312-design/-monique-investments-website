/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/
import React from 'react';
import PropTypes from 'prop-types'; // Added import statement for PropTypes

import gettext from 'sources/gettext';

const MetricTable = (props) => {
  const { metrics } = props;
  return (
    <table>
      <thead>
        <tr >
          <th className='tableHeader' colSpan={2}>{gettext('Selected Metrics')}</th>
        </tr>
        <tr>
          <th>{gettext('Metrics')}</th>
          <th>{gettext('Metric Details')}</th>
        </tr>
      </thead>
      <tbody>
        {metrics?.length && metrics?.map((m) => (
          <tr key={m.id}>
            <td>{m.metric_display_name}</td>
            <td>
              <div className='internalTable'>
                <div className='label'>
                  {gettext('Display Name')}:
                </div>
                <div>
                  {`${m.metric_display_name} (${m.metric_object})`}
                </div>
                <div className='label'>
                  {gettext('Probe')}:
                </div>
                <div>
                  {m.probe_display}
                </div>
                <div className='label'>
                  {gettext('Metric')}:
                </div>
                <div>
                  {m.metric_display_name}
                </div>
                <div className='label'>
                  {gettext('Host')}:
                </div>
                <div>
                  {m.obj}
                </div>
              </div>
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
};

MetricTable.propTypes = {
  metrics: PropTypes.array.isRequired, // Added prop validation for metrics
};

export default MetricTable;

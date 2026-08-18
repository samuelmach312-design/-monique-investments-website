///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import moment from 'moment';
import PropTypes from 'prop-types';
import url_for from 'sources/url_for';
import gettext from 'sources/gettext';
import pgAdmin from 'sources/pgadmin';
import getApiInstance from 'sources/api_instance';
import SchemaView from 'sources/SchemaView';
import { ENDPOINTS } from 'pem/common/constants';
import AlertHistorySchema from './AlertHistorySchema.ui';
import { TIMEFRAMES } from './constants';

export default function AlertHistoryMenu({ closeDialog }) {
  const alertHistorySchema = React.useRef(null);
  if (!alertHistorySchema.current) {
    alertHistorySchema.current = new AlertHistorySchema();
  }
  const api = React.useMemo(() => getApiInstance(), []);

  const generateReport = (isNew, data) => {
    const servers = [];
    const agents = [];
    let overall_report = false;
    data.server_agents.forEach((element) => {
      if (element === 'overall_report') {
        overall_report = true;
      } else {
        const [type, id] = element.split('-');
        const numericId = +id;
        if (type === 'server') servers.push(numericId);
        else if (type === 'agent') agents.push(numericId);
      }
    });
    return new Promise((resolve, reject) => {
      api
        .post(url_for(ENDPOINTS.REPORTS.ALERT_HISTORY.GENERATE_REPORT), {
          agents,
          servers,
          overall_report,
          alert_types: data.alert_types,
          timeframe: data.timeframe || TIMEFRAMES.tweleveHours,
        })
        .then((res) => {
          if (res.status !== 200) {
            reject(
              new Error(gettext('Error occurred while generating the report.'))
            );
            return;
          }

          const pollReport = () => {
            api
              .get(
                url_for(ENDPOINTS.REPORTS.ALERT_HISTORY.POLL, {
                  trans_id: res.data.data.trans_id,
                })
              )
              .then((pollRes) => {
                if (pollRes.data.data.status === 'busy') {
                  setTimeout(pollReport, 500);
                } else if (pollRes.data.data.status === 'completed') {
                  api
                    .get(
                      url_for(ENDPOINTS.REPORTS.ALERT_HISTORY.DOWNLOAD, {
                        trans_id: res.data.data.trans_id,
                      }),
                      { responseType: 'json' }
                    )
                    .then((downloadRes) => {
                      const timestamp = moment().format('YYYY-MM-DD_HH-mm-ss');

                      const fileName = `Alert_History_Report_${timestamp}.json`;

                      const blob = new Blob(
                        [JSON.stringify(downloadRes.data)],
                        {
                          type: 'application/json',
                        }
                      );
                      const url = URL.createObjectURL(blob);

                      const link = document.createElement('a');
                      link.href = url;
                      link.download = fileName;
                      document.body.appendChild(link);
                      link.click();

                      document.body.removeChild(link);
                      URL.revokeObjectURL(url);

                      closeDialog();
                      resolve(res.data);
                    })
                    .catch((err) => {
                      pgAdmin.Browser.notifier.pgNotifier(
                        'error-noalert',
                        gettext(
                          'Error occurred while downloading the report: %s',
                          err.message
                        ),
                        ''
                      );
                      reject(err);
                    });
                }
              })
              .catch((pollErr) => {
                reject(pollErr);
              });
          };

          pollReport();
        })
        .catch((err) => {
          pgAdmin.Browser.notifier.pgNotifier(
            'error-noalert',
            gettext(
              'Error occurred while generating the report: %s',
              err.message
            ),
            ''
          );
          reject(err);
        });
    });
  };

  return (
    <SchemaView
      formType="dialog"
      getInitData={() => Promise.resolve(
        {
          timeframe: TIMEFRAMES.tweleveHours,
        }
      )}
      loadingText={gettext('Loading...')}
      viewHelperProps={{ mode: 'edit' }}
      schema={alertHistorySchema.current}
      showFooter={true}
      isTabView={false}
      onClose={closeDialog}
      onSave={generateReport}
      customSaveBtnName={gettext('Download')}
      disableSqlHelp={true}
    />
  );
}

AlertHistoryMenu.propTypes = {
  closeDialog: PropTypes.func,
};

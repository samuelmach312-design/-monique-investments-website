///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState, useEffect } from 'react';
import DescriptionIcon from '@mui/icons-material/Description';
import CachedIcon from '@mui/icons-material/Cached';
import FilterAltIcon from '@mui/icons-material/FilterAlt';
import PropTypes from 'prop-types';
import SectionContainer from 'top/dashboard/static/js/components/SectionContainer';
import ChartButton from '../Charts/Common/Buttons/ChartButton';
import Loader from 'sources/components/Loader';
import PgTable from 'sources/components/PgTable';
import url_for from 'sources/url_for';
import gettext from 'sources/gettext';
import { StyledErrorDiv } from 'pem.charts/Common/StyledComponents';
import { StyledWarningIcon } from 'pem/common/StyledComponents';
import LogViewerFilter from './LogViewerFilter';
import {
  StyledLogViewerFilterWrapper,
  StyledPgTableCell,
} from './styledComponents';
import MarkdownParser from 'pem/modules/Monitoring/Common/MarkdownParser';
import getApiInstance from 'sources/api_instance';
import { LOG_VIEWER_CONSTANTS } from './constants';

function LogViewer({ logViewerProperties }) {
  const [logData, setLogData] = useState({ columns: [], data: [] });
  const [loading, setLoading] = useState(false);
  const [openFilter, setOpenFilter] = useState(false);
  const [error, setError] = useState('');

  const api = getApiInstance();

  const getColumnSize = (name) => {
    switch (name) {
    case 'Message':
      return 300;
    case 'Probe Name':
    case 'Timestamp':
    case 'Command':
      return 100;
    case 'id':
      return 80;
    default:
      if (/\bid\b/i.test(name)) return 100;
      if (/\bmessage\b/i.test(name)) return 300;
      return 150;
    }
  };

  const fetchData = (filters = {}, refreshClicked = false) => {
    if (refreshClicked) setLoading(true);

    const url = url_for(logViewerProperties.url, {
      row_id: 0,
      ...logViewerProperties.api_params,
    });

    const urlWithFilters = _.isEmpty(filters)
      ? url
      : Object.entries(filters).reduce((baseUrl, [key, value]) => {
        return value ? `${baseUrl}/${key.toLowerCase()}/${value}` : baseUrl;
      }, url);

    api
      .get(urlWithFilters)
      .then(({ data }) => {
        const { columns, data: tableData } = data?.data || {};
        setLogData({
          columns: columns.map((item) => ({
            accessorKey: item.name,
            header: gettext(item.display_name),
            enableSorting: true,
            enableResizing: true,
            enableFilters: true,
            size: getColumnSize(item.name),
            cell: ({ getValue }) => (
              <StyledPgTableCell>
                {item.type_code === 1700
                  ? new Date(Number(getValue())).toLocaleString('en-GB', {
                    hour12: false,
                  })
                  : getValue()}
              </StyledPgTableCell>
            ),
          })),
          data: tableData,
        });
        setOpenFilter(false);
        setLoading(false);
      })
      .catch((err) => {
        setLoading(false);
        setOpenFilter(false);
        setError(err?.response?.data?.error || err?.response?.data?.errormsg);
      });
  };

  useEffect(() => {
    fetchData();
  }, []);

  return (
    <SectionContainer
      title={gettext(logViewerProperties.label)}
      style={{ marginTop: '10px' }}
      titleExtras={
        <div style={{ display: 'flex'}}>
          <ChartButton
            title={<MarkdownParser description={logViewerProperties.tooltip} />}
            Icon={DescriptionIcon}
            openSettings={false}
            id={LOG_VIEWER_CONSTANTS.DESCRIPTION}
          />
          <ChartButton
            title={LOG_VIEWER_CONSTANTS.REFRESH}
            Icon={CachedIcon}
            clickAction={() => {
              setError('');
              setOpenFilter(false);
              fetchData({}, true);
            }}
            openSettings={false}
            id={LOG_VIEWER_CONSTANTS.REFRESH}
          />
          <ChartButton
            title={LOG_VIEWER_CONSTANTS.FILTER}
            Icon={FilterAltIcon}
            clickAction={() => setOpenFilter((prev) => !prev)}
            openSettings={false}
            id={LOG_VIEWER_CONSTANTS.FILTER}
          />
        </div>
      }
    >
      {loading && <Loader message={LOG_VIEWER_CONSTANTS.LOADING} />}
      {error ? (
        <StyledErrorDiv>
          <StyledWarningIcon /> {error}
        </StyledErrorDiv>
      ) : (
        <PgTable
          caveTable={false}
          columns={logData?.columns}
          type={'panel'}
          data={logData?.data}
          tableNoBorder={false}
          showSearch={false}
          variant='logViewer'
          className='pgtable-log-viewer-filter-section'
          customHeader={
            <StyledLogViewerFilterWrapper openFilter={openFilter.toString()}>
              <LogViewerFilter
                fetchData={fetchData}
                filters={logViewerProperties.filters}
              />
            </StyledLogViewerFilterWrapper>
          }
        />
      )}
    </SectionContainer>
  );
}

LogViewer.propTypes = {
  logViewerProperties: PropTypes.object.isRequired,
};

export default LogViewer;

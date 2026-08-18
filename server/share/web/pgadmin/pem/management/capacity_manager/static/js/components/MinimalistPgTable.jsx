///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import { StyledDiv } from './StyledComponents';

export function MinimalisticPgTable({ columns, data, showFooter = false }) {
  return (
    <StyledDiv className="pgrt">
      <div
        className="pgrt-table"
        style={{ gridTemplateColumns: `repeat(${columns.length}, 1fr)` }}
      >
        <div className="pgrt-header">
          <div className="pgrt-header-row">
            {columns.map((column) => (
              <div key={column.accessor} className="pgrt-header-cell">
                <div>{column.header}</div>
              </div>
            ))}
          </div>
        </div>

        <div className="pgrt-body">
          {data?.map((row, rowIndex) => (
            <div
              key={rowIndex}
              className={`pgrt-row ${
                showFooter && rowIndex === data.length - 1
                  ? 'pgrt-footer-row'
                  : ''
              }`}
            >
              {columns.map((column) => (
                <div key={column.accessor} className="pgrd-row-cell">
                  {row[column.accessor] !== undefined &&
                  row[column.accessor] !== null
                    ? row[column.accessor]
                    : 'N/A'}
                </div>
              ))}
            </div>
          ))}
        </div>
      </div>
    </StyledDiv>
  );
}

MinimalisticPgTable.propTypes = {
  columns: PropTypes.arrayOf(
    PropTypes.shape({
      header: PropTypes.string.isRequired,
      accessor: PropTypes.string.isRequired,
    })
  ).isRequired,
  data: PropTypes.arrayOf(PropTypes.object).isRequired,
  showFooter: PropTypes.bool,
};

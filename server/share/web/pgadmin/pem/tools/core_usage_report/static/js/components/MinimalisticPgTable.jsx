///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import { styled } from '@mui/material/styles';

const StyledDiv = styled('div')(({ theme }) => ({
  '&.pgrt': {
    display: 'block',
    overflow: 'auto',
    position: 'relative',
    flexGrow: 1,
    border: `1px solid ${theme.palette.divider}`,
    borderRadius: theme.shape.borderRadius,
  },
  '& .pgrt-table': {
    display: 'grid',
    gridAutoRows: 'auto',
    gridTemplateColumns: 'repeat(auto-fit, minmax(100px, 1fr))',
    backgroundColor: theme.otherVars.tableBg,
  },
  '& .pgrt-header': {
    display: 'contents',
    '& .pgrt-header-row': {
      display: 'contents',
      '& .pgrt-header-cell': {
        fontWeight: theme.typography.fontWeightBold,
        padding: theme.spacing(1),
        textAlign: 'left',
        backgroundColor: theme.palette.grey[200],
        borderBottom: `1px solid ${theme.palette.divider}`,
        borderRight: `1px solid ${theme.palette.divider}`,
        '&:last-child': {
          borderRight: 'none',
        },
      },
    },
  },
  '& .pgrt-body': {
    display: 'contents',
    '& .pgrt-row': {
      display: 'contents',
      '& .pgrd-row-cell': {
        padding: theme.spacing(1),
        borderBottom: `1px solid ${theme.palette.divider}`,
        borderRight: `1px solid ${theme.palette.divider}`,
        '&:last-child': {
          borderRight: 'none',
        },
      },
    },
  },
  '& .pgrt-footer-row': {
    display: 'contents',
    fontWeight: theme.typography.fontWeightBold,
    backgroundColor: theme.palette.grey[100],
    '& .pgrd-row-cell': {
      borderBottom: 'none',
    },
  },
}));

export function MinimalisticPgTable({ columns, data, showFooter = false }) {
  return (
    <StyledDiv className="pgrt">
      <div
        className="pgrt-table"
        style={{ gridTemplateColumns: `repeat(${columns.length}, 1fr)` }}
      >
        {/* Header */}
        <div className="pgrt-header">
          <div className="pgrt-header-row">
            {columns.map((column) => (
              <div key={column.accessor} className="pgrt-header-cell">
                <div>{column.header}</div>
              </div>
            ))}
          </div>
        </div>

        {/* Body */}
        <div className="pgrt-body">
          {data.map((row, rowIndex) => (
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

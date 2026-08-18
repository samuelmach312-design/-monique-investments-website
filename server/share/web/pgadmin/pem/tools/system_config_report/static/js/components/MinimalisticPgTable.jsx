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
    backgroundColor: theme.palette.background.paper,
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
  '& .nested-list': {
    margin: 0,
    listStyleType: 'disc',
  },
  '& .nested-list li': {
    marginBottom: theme.spacing(0.5),
  },
}));

export function MinimalisticPgTable({ columns, data }) {
  let gridTemplateColumns;

  if (columns.length > 3) {
    gridTemplateColumns = columns.map(() => '1fr').join(' ');
  } else {
    gridTemplateColumns = [
      'minmax(auto, 30%)',
      ...Array(columns.length - 1).fill('1fr'),
    ].join(' ');
  }

  return (
    <StyledDiv className='pgrt'>
      <div className='pgrt-table' style={{ gridTemplateColumns }}>
        {/* Header */}
        <div className='pgrt-header'>
          <div className='pgrt-header-row'>
            {columns.map((column) => (
              <div key={column.accessor} className='pgrt-header-cell'>
                <div>{column.header}</div>
              </div>
            ))}
          </div>
        </div>

        {/* Body */}
        <div className='pgrt-body'>
          {data.map((row, rowIndex) => (
            <React.Fragment key={rowIndex}>
              <div className='pgrt-row'>
                {columns.map((column) => (
                  <div key={column.accessor} className='pgrd-row-cell'>
                    {/* Check if the value is an object */}
                    {typeof row[column.accessor] === 'object' &&
                    row[column.accessor] !== null ? (
                        <ul className='nested-list'>
                          {Object.entries(row[column.accessor]).map(
                            ([key, val]) => (
                              <li key={key}>
                                <strong>
                                  {key.charAt(0).toUpperCase() + key.slice(1)}:
                                </strong>{' '}
                                {val}
                              </li>
                            )
                          )}
                        </ul>
                      ) : row[column.accessor] !== undefined &&
                      row[column.accessor] !== null ? (
                          row[column.accessor]
                        ) : (
                          'N/A'
                        )}
                  </div>
                ))}
              </div>
            </React.Fragment>
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
};

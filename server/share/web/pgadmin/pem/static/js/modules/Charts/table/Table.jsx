///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import { useReactTable, getCoreRowModel } from '@tanstack/react-table';
import { StyledTable } from 'pem.charts/Common/StyledComponents';
import PropTypes from 'prop-types';
import gettext from 'sources/gettext';

const Table = ({ tableData, emptyTableMessage }) => {
  const nestedTable = useReactTable({
    data: tableData.data,
    columns: tableData.columns,
    getCoreRowModel: getCoreRowModel(),
  });

  const rows = nestedTable.getRowModel().rows;
  const hasNoData = rows.length === 0;

  return (
    <StyledTable>
      <thead>
        {nestedTable.getHeaderGroups().map((headerGroup) => (
          <tr key={headerGroup.id} className='tableRow'>
            {headerGroup.headers.map((header) => (
              <th key={header.id} className='tableHeader'>
                {!header.isPlaceholder && header.column.columnDef.header}
              </th>
            ))}
          </tr>
        ))}
      </thead>
      <tbody>
        {hasNoData ? (
          <tr className='tableRow'>
            <td colSpan={tableData.columns.length} className='tableRowNoData'>
              {gettext(emptyTableMessage)}
            </td>
          </tr>
        ) : (
          rows.map((row) => (
            <tr key={row.id} className='tableRow'>
              {row.getVisibleCells().map((cell) => (
                <td
                  key={cell.id}
                  className='tableData'
                  title={
                    cell.column.columnDef?.disableTooltip
                      ? ''
                      : String(cell.getValue() ?? '')
                  }
                >
                  {gettext(cell.getValue())}
                </td>
              ))}
            </tr>
          ))
        )}
      </tbody>
    </StyledTable>
  );
};

Table.propTypes = {
  tableData: PropTypes.object.isRequired,
  emptyTableMessage: PropTypes.string.isRequired,
};

export default Table;

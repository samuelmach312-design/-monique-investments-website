///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import Feature from './feature';


export default class ColumnGroup extends Feature {
  static priority = 1000;

  generateColumns({columns}) {
    const colGroups = {};
    const res = [];
    
    columns.forEach((col) => {
      if (col.field?.colGroup) {
        let colGroup = colGroups[col.field.colGroup];
        if (!colGroup) {
          colGroup = colGroups[col.field.colGroup] = {
            header: col.field.colGroup,
            columns: [],
            minSize: 0,
            size: 0, 
          };
          res.push(colGroup);
        }
    
        colGroup.minSize += col.field.minWidth || 0;
        colGroup.size += col.field.width || 0;
    
        colGroup.columns.push(col);
        return;
      }

      res.push({
        header: ' ',
        columns: [col],
        minSize: col.size || 0,
        size: col.minSize || 0,
      });
    });

    if (Object.keys(colGroups).length) {
      columns.splice(0, columns.length, ...res);
    }
  }

}

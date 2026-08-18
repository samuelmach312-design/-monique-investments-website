/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2025, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////

// The DataGridView component is feature support better extendability.

import { Feature, FeatureSet, register } from './feature';
import Paginator from './paginator';
import FixedRows from './fixedRows';
import Reorder from './reorder';
import ExpandedFormView from './expandabledFormView';
import DeletableRow from './deletable';
import GlobalSearch from './search';
import SeletableRow from './selectable';
import ColumnFilter from './columnFilter';
import ColumnGroup from './column_groups';
import ColumnSorter from './columnSort';
import OpenInDialog from './openInDialog';
import QuickDeleteRow from './instantDelete';

register(Paginator);
register(FixedRows);
register(DeletableRow);
register(QuickDeleteRow);
register(ExpandedFormView);
register(SeletableRow);
register(GlobalSearch);
register(ColumnFilter);
register(OpenInDialog);
register(Reorder);
register(ColumnGroup);
register(ColumnSorter);

export {
  Feature,
  FeatureSet,
  register
};

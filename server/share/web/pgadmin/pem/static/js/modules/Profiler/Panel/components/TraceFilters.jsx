////////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
////////////////////////////////////////////////////////////////////////////////

import React, { useMemo, useState } from 'react';
import PropTypes from 'prop-types';

import SchemaView from '../../../../../../../static/js/SchemaView';
import TraceFilterSchema from '../../schemas/trace_filter.ui';
import { PgButtonGroup, PgIconButton } from '../../../../../../../static/js/components/Buttons';
import { styled } from '@mui/material';
import SaveIcon from '@mui/icons-material/Save';
import FolderOpenRoundedIcon from '@mui/icons-material/FolderOpenRounded';
import Loader from 'sources/components/Loader';

import gettext from 'sources/gettext';
import { usePgAdmin } from 'sources/PgAdminProvider';
import { FILTER_COLUMNS } from '../constants';


const Root = styled('div')(()=>({
  display: 'flex',
  flexDirection: 'column',
  height: '100%',

  '& .TraceFilters-header': {
    padding: '4px',
    display: 'flex',
  },
  '& .FormView-singleCollectionPanel.TraceFilters-form': {
    padding: 0,
  }
}));

const filterColumnOptions = FILTER_COLUMNS.map((c)=>({
  label: c.name, value: c.tableAlias ? `${c.tableAlias}.${c.key}` : c.key,
}));

export default function TraceFilters({data, profilerCtx, onClose, onApply, modal}) {
  // alias is required by backend SQLs
  const pgAdmin = usePgAdmin();
  // remove the row number
  const schemaObj = useMemo(()=>new TraceFilterSchema(data, filterColumnOptions), []);
  const [changedData, setChangedData] = useState({});
  const [loaderText, setLoaderText] = useState('');

  const onSaveClick = async (isNew, data)=>{
    await profilerCtx.utils.applyFilter(data);

    let filtersText = '';
    if(data.filter?.length > 0) {
      filtersText = gettext('Filters:') + ' ' + data?.filter?.
        map((f)=>`${filterColumnOptions.find((c)=>c.value == f.type).label}: ${f.condition} ['${f.value}']`)
        .join(', ');
    }
    onApply?.(data, filtersText);
    onClose();
  };

  const onOpenFile = ()=>{
    let fileParams = {
      'supported_types': ['json', '*'],
      'dialog_type': 'select_file',
    };
    pgAdmin.Tools.FileManager.show(fileParams, async (fileName)=>{
      const resp = await profilerCtx.utils.loadFilterFile(fileName);
      if(resp.status) {
        schemaObj.state.setUnpreparedData(['filter'], resp.result.filter);
      }
    }, null, modal);
  };

  const onSaveFile = ()=>{
    let fileParams = {
      'supported_types': ['json', '*'],
      'dialog_type': 'create_file',
    };
    pgAdmin.Tools.FileManager.show(fileParams, async (fileName)=>{
      setLoaderText(gettext('Saving file...'));
      await profilerCtx.utils.saveFilterFile(changedData.data.filter, fileName);
      setLoaderText('');
    }, null, modal);
  };

  return (
    <Root>
      <Loader message={loaderText} />
      <div className='TraceFilters-header'>
        <PgButtonGroup size="small">
          <PgIconButton data-test='start' title={gettext('Open filters file')} icon={<FolderOpenRoundedIcon />}
            onClick={onOpenFile} />
          <PgIconButton data-test='stop' title={gettext('Save filters to file')} icon={<SaveIcon />}
            disabled={changedData.hasError} onClick={onSaveFile} />
        </PgButtonGroup>
      </div>
      {useMemo(()=><SchemaView
        formClassName = 'TraceFilters-form'
        formType='dialog'
        getInitData={()=>Promise.resolve({})}
        schema={schemaObj}
        viewHelperProps={{
          mode: 'create'
        }}
        onDataChange={(_isDirty, data, error)=>{
          setChangedData({
            hasError: Boolean(error?.message),
            data: data,
          });
        }}
        isTabView={false}
        onSave={onSaveClick}
        onClose={onClose}
        customSaveBtnIconType='done'
        customSaveBtnName={gettext('Apply')}
      />, [])}
    </Root>
  );
}

TraceFilters.propTypes = {
  data: PropTypes.object,
  profilerCtx: PropTypes.object,
  onClose: PropTypes.func,
  onApply: PropTypes.func,
  modal: PropTypes.object,
};

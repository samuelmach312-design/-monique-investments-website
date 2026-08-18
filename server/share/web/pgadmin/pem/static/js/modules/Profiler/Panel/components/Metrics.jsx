////////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
////////////////////////////////////////////////////////////////////////////////

import React, { useContext, useState } from 'react';
import { Box, styled, LinearProgress } from '@mui/material';

import { ProfilerContext } from '..';
import { useDelayDebounce } from '../../../../../../../static/js/custom_hooks';
import Loader from 'sources/components/Loader';
import gettext from 'sources/gettext';
import { usePgAdmin } from 'sources/PgAdminProvider';
import { parseApiError } from '../../../../../../../static/js/api_instance';


const KEY_MAPPING = [
  {
    key: 'executed',
    label: gettext('Executed'),
    progressBar: false,
  },
  {
    key: 'execution',
    label: gettext('Execution'),
    progressBar: true,
  },
  {
    key: 'duration',
    label: gettext('Duration'),
    progressBar: true,
  },
  {
    key: 'rows_updated',
    label: gettext('Rows Affected'),
    progressBar: true,
  },
  {
    key: 'page_faults',
    label: gettext('Page Faults'),
    progressBar: true,
  },
  {
    key: 'page_reclaims',
    label: gettext('Page Reclaims'),
    progressBar: true,
  },
  {
    key: 'swaps',
    label: gettext('Swaps'),
    progressBar: true,
  },
  {
    key: 'fs_in',
    label: gettext('File System In'),
    progressBar: true,
  },
  {
    key: 'fs_out',
    label: gettext('File System Out'),
    progressBar: true,
  },
  {
    key: 'sign_recv',
    label: gettext('Signals Received'),
    progressBar: true,
  },
  {
    key: 'msg_recv',
    label: gettext('Messages Received'),
    progressBar: true,
  },
  {
    key: 'msg_snd',
    label: gettext('Messages Sent'),
    progressBar: true,
  },
  {
    key: 'vol_contx_switch',
    label: gettext('Voluntary Context Switches'),
    progressBar: true,
  },
  {
    key: 'invol_contx_switch',
    label: gettext('Involuntary Context Switches'),
    progressBar: true,
  },
  {
    key: 'shared_blk_read',
    label: gettext('Shared Blocks Read'),
    progressBar: true,
  },
  {
    key: 'shared_blk_written',
    label: gettext('Shared Blocks Written'),
    progressBar: true,
  },
  {
    key: 'shared_blk_hit',
    label: gettext('Shared Blocks Hit'),
    progressBar: true,
  },
  {
    key: 'local_blk_read',
    label: gettext('Local Blocks Read'),
    progressBar: true,
  },
  {
    key: 'local_blk_written',
    label: gettext('Local Blocks Written'),
    progressBar: true,
  },
  {
    key: 'local_blk_hit',
    label: gettext('Local Blocks Hit'),
    progressBar: true,
  },
  {
    key: 'tmp_blk_read',
    label: gettext('Temporary Blocks Read'),
    progressBar: true,
  },
  {
    key: 'tmp_blk_written',
    label: gettext('Temporary Blocks Read'),
    progressBar: true,
  }
];

const ListItem = styled(Box)(({theme}) => ({
  padding: '8px 4px',
  borderBottom: '1px solid' + theme.otherVars.borderColor,
  display: 'flex',
  alignItems: 'center',
  gap: '12px',
  '& .ListItem-label': {
    width: '30%',
  },
  '& .ListItem-progress': {
    flexGrow: 1,
  },
  '& .ListItem-value': {
    width: '10%',
  },
  '& .MuiLinearProgress-root': {
    height: '12px',
    borderRadius: theme.shape.borderRadius,
  }
}));

export default function Metrics() {
  const pgAdmin = usePgAdmin();
  const profilerCtx = useContext(ProfilerContext);
  const [data, setData] = useState();
  const [loaderText, setLoaderText] = useState('');

  useDelayDebounce(async (row)=>{
    if(row) {
      setLoaderText('Loading...');
      try {
        const resp = await profilerCtx.utils.fetchMetrics(row.query_id);
        setData(resp.data);
      } catch (error) {
        pgAdmin.Browser.notifier.error(`Failed in metrics: ${parseApiError(error)}`);
        setData(null);
      }
      setLoaderText('');
    }
  }, profilerCtx.state.selectedRow, 200);

  if(!data) {
    return <></>;
  }

  return (
    <>
      <Loader message={loaderText} />
      <Box height="100%" overflow="auto">
        {KEY_MAPPING.map((item)=>{
          return (
            <ListItem key={item.key}>
              <Box className='ListItem-label'><span>{item.label}</span></Box>
              <Box className='ListItem-progress'>
                {item.progressBar && <LinearProgress variant='determinate' value={data[item.key]} />}
              </Box>
              <Box className='ListItem-value'>{data[item.key]}{item.progressBar && '%'}</Box>
            </ListItem>
          );
        })}
      </Box>
    </>
  );
}

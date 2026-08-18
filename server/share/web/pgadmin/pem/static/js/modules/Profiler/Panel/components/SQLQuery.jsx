////////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
////////////////////////////////////////////////////////////////////////////////

import React, { useContext } from 'react';
import { ProfilerContext } from '..';
import CodeMirror from '../../../../../../../static/js/components/ReactCodeMirror';

export default function SQLQuery() {
  const profilerCtx = useContext(ProfilerContext);

  return <CodeMirror
    value={profilerCtx.state.selectedRow?.query ?? ''}
    readonly
    showCopyBtn
    options={{
      lineNumbers: false,
      foldGutter: false
    }}
  />;
}

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

export default function TextPlan() {
  const profilerCtx = useContext(ProfilerContext);

  return <CodeMirror
    language="json"
    value={profilerCtx.state.selectedRow?.explain ?? ''}
    readonly
    showCopyBtn
    options={{
      lineNumbers: false,
    }}
  />;
}

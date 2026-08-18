////////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
////////////////////////////////////////////////////////////////////////////////

import React, { useContext } from 'react';
import { ProfilerContext } from '..';
import Explain from '../../../../../../../static/js/Explain';

export default function GraphicalPlan() {
  const profilerCtx = useContext(ProfilerContext);
  const plans = profilerCtx.state.selectedRow?.explain ?  [JSON.parse(profilerCtx.state.selectedRow?.explain)] : [];
  return <Explain plans={plans} emptyMessage='' />;
}

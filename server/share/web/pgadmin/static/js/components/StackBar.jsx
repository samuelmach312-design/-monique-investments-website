/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

import React from 'react';
import { styled } from '@mui/material/styles';
import { Tooltip } from '@mui/material';
import Stack from '@mui/material/Stack';
import PropTypes from 'prop-types';

const StyledStackSpan = styled('span')(({theme}) => ({
  width: '100%',
  display: 'inline-flex',
  alignItems: 'center',
  '& > div': {
    directio:'row',
    alignItems: 'center',
    width: '100%',
    '& > div': {
      height: theme.spacing(1.25),
      width: '100%',
    },
  },
}));

const StyledStackDiv = styled('div')(({theme, ...props}) => ({
  width: props.data.percentage + '%',
  height: 10,
  backgroundColor: props.data.color,
  display: 'inline-block',
  borderTopLeftRadius: props.data.leftRadius == true ? theme.spacing(0.625) : '',
  borderBottomLeftRadius: props.data.leftRadius == true ? theme.spacing(0.625) : '',
  borderTopRightRadius: props.data.rightRadius == true ? theme.spacing(0.625) : '',
  borderBottomRightRadius: props.data.rightRadius == true ? theme.spacing(0.625) : '',
}));

export default function StackBar({data}) {
  return (
    <StyledStackSpan>
      <Stack>
        <div>
          {data.map((wait, index) => (
            <Tooltip key={index}  title={wait['tooltip']}>
              <StyledStackDiv data={wait} key={wait['color']}/>
            </Tooltip>
          ))}
        </div>
      </Stack>
    </StyledStackSpan>);

}
StackBar.propTypes = {
  data: PropTypes.array,
};

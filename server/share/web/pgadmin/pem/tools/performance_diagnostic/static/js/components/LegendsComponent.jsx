///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState, useMemo } from 'react';
import { Box, Grid } from '@mui/material';
import { styled } from '@mui/material/styles';
import SquareIcon from '@mui/icons-material/Square';
import CropSquareIcon from '@mui/icons-material/CropSquare';
import PropTypes from 'prop-types';
import { DefaultButton } from 'sources/components/Buttons';

const StyledBox = styled(Box)(({theme}) => ({
  '& .LegendContainer': {
    padding: theme.spacing(0.5),
    '& div': {
      marginLeft: 'auto',
      marginRight: 'auto',
      maxWidth: 'fit-content',
      '& > div': {
        display: 'flex',
        flexWrap: 'wrap',
        fontWeight: 'normal',
        '& .legendValue': {
          '& .legendLabel': {
            marginLeft: theme.spacing(0.5),
          },
        },
        '& > button': {
          marginLeft: theme.spacing(1.25),
        }
      }
    }
  }
}));

export default function LegendsComponent({legends, onChange}) {
  const [activeLegends, setActiveLegends] = useState([]);

  useMemo(() => {
    let _activeLegends = [];
    Object.keys(legends).map(leg => {
      _activeLegends[leg] = true;
    });
    setActiveLegends(_activeLegends);
  }, [legends]);


  const onLegendClick = function(_target) {
    let d = {};
    if (_target in activeLegends) {
      d[_target] = !activeLegends[_target];
    } else {
      d[_target] = true;
    }
    let latestLegends = Object.assign({}, activeLegends, d);
    setActiveLegends(latestLegends);
    onChange(latestLegends);
  };


  return (
    <StyledBox>
      <Grid size={{ md: 12 }} className='LegendContainer'>
        <div>
          <div>
            {legends && Object.keys(legends).map((datum)=>(
              <DefaultButton key={datum}  onClick={()=>onLegendClick(datum)}>
                <div className="legendValue">
                  <span>
                    { activeLegends[datum] === true ?
                      <SquareIcon fontSize="small"  sx={{ color: legends[datum] }}/> :
                      <CropSquareIcon fontSize="small"  sx={{ color: legends[datum] }}/>
                    }
                  </span>
                  <span className="legendLabel">{datum}</span>
                </div>
              </DefaultButton>
            ))}
          </div>
        </div>
      </Grid>
    </StyledBox>
  );

}
LegendsComponent.propTypes = {
  legends: PropTypes.object,
  onChange: PropTypes.any,
};

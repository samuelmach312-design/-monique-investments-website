/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

// Reference: https://leeoniya.github.io/uPlot/demos/bars-grouped-stacked.html

import React, { useMemo } from 'react';
import UplotReact from 'uplot-react';
import { useResizeDetector } from 'react-resize-detector';
import { styled } from '@mui/material/styles';
import { useTheme } from '@mui/material';
import _ from 'lodash';
import PropTypes from 'prop-types';
import seriesBarsPlugin, {stack} from './StackedBarUtils/GroupedBars';
import axisIndicsPlugin from './StackedBarUtils/axisIndicsPlugin';

const StyledDiv = styled('div')(({theme})=>({
  ...theme.mixins.tabPanel,
  height:'100%',
  width:'100%',
  backgroundColor: theme.backgroundColor,
  '& .u-select': {
    pointerEvents: 'all',
    cursor: 'grabbing',
    height: '105% !important',
    background: theme.palette.primary.main + '33',
  },
  '& .u-grip-l': {
    position: 'absolute',
    left: theme.spacing(-0.625),
    width: theme.spacing(0.625),
    height: '100%',
    background: theme.palette.primary.main,
    cursor: 'ew-resize',
  },
  '& .u-grip-r': {
    position: 'absolute',
    right: theme.spacing(-0.625),
    width: theme.spacing(0.625),
    height: '100%',
    background: theme.palette.primary.main,
    cursor: 'ew-resize',
  },
  '& .uplot .cursor-pt': {
    pointerEvents: 'auto !important;',
  },
  '& .title': {
    fontWeight: 'bold',
  },
  '& .u-indic-x, & .u-indic-y': {
    color: theme.palette.primary.contrastText,
    position: 'absolute !important',
    textAlign: 'center !important',
    fontSize: theme.spacing(1.5) + ' !important',
    padding: theme.spacing(0.5, 1) + ' !important',
    lineHeight: theme.spacing(1.75) + ' !important',
    borderRadius: theme.spacing(0.375) + ' !important',
    display: 'none',
    top: theme.spacing(1.25),
    backgroundColor: theme.palette.primary.main + ' !important',
  },
  '& .u-indic-y .u-indic-line': {
    position: 'absolute',
    top: '50%',
    left: '100%',
    borderBottom: '1px dashed transparent',
    width: theme.spacing(12.5),
  },
  '& .u-wrap': {
    overflow: 'hidden',
  },
}));


export default function StackedBars({data, options}) {
  const theme = useTheme();
  const { width, height, ref:containerRef } = useResizeDetector({
    handleHeight: false,
  });
  const ori = options.ori || 0;
  const dir = options.dir || 1;
  const stacked = options.stacked || true;
  const initXmin = options.zoomCoordinates?.left || 0;
  const onZoomFunc = options.onZoomFunc || undefined;
  const onClickFunc = options.onClickFunc || undefined;
  const maxXPoints = options.maxXPoints || 10;
  const lftWid = {left: null, width: null};
  const uRanger = React.useRef();

  let newHeight = height, x0, lft0, wid0;
  let newWidth = width - 10;
  let showStackLabel = options.showStackLabel || false;


  // Default Options
  const defaultOptions = useMemo(()=> {

    const initialState = [
      data.timeline,
      ...(data.datasets?.map((d)=>{
        let ret = new Array(d.data.length).fill(null);
        ret.splice(0, d.data.length, ...d.data);
        return ret;
      })??{}),
    ];

    let maxValues = initialState.map((d, k)=>{
      if (k == 0) return 0;
      return Math.max(...d);
    });

    let maxYRange = maxValues.reduce(function (x, y) {
      return x + y;
    }, 0);

    const series = [
      {},
      ...(data.datasets?.map((datum) => ({
        label: datum.label,
        fill: datum.borderColor,
        width: 1,
      })) ?? []),
    ];


    let _finalData = stack(initialState, () => false);
    let bands = _finalData['bands'];
    let finalData = _finalData['finalData'];

    const yAxesValueFormater = (self, values) => {
      const maxPointDivider = Math.round(values.length / maxXPoints);
      let _values = values.length < maxXPoints ? values : values?.map((val, num)=>{
        if (num % maxPointDivider == 0) {
          return val;
        }
      });
      return _values ?? [];
    };

    const customAxes = [
      {
        rotate: 0,
        stroke: theme.palette.text.primary,
      },
      {
        side: ori == 0 ? 3 : 0,
        label: options.labelY || '',
        labelSize: 20,
        stroke: theme.palette.text.primary,
        labelGap: 2,
      },
    ];

    let _opts = {
      width: width,
      height: newHeight,
      padding: [null, 0, null, 0],
      focus: {
        alpha: 0.3,
      },
      legend: {
        live: false,
        markers: {
          width: 0,
        }
      },
      bands,
      series: series,
      scales: {
        x: {
          time: true,
        },
        y: {
          range: [0, maxYRange],
          ori: ori == 0 ? 1 : 0,
        }
      },
      axes: customAxes,
      plugins: [
        seriesBarsPlugin({
          ori,
          dir,
          stacked,
          showStackLabel,
          yAxesValueFormater,
        }),
        axisIndicsPlugin(customAxes, stacked),
      ],
    };

    if (onZoomFunc) {
      _opts = _.merge(_opts, {
        width: newWidth,
        select: {show: true},
        cursor: {
          x: false,
          y: false,
          points: {
            show: false,
          },
          drag: {
            setScale: false,
            setSelect: true,
            x: true,
            y: false,
          },
          bind: {
            dblclick: () => { return; },
          },
        },
        hooks: {
          ready: [
            uRanger => {
              const parent = uRanger.root.querySelector('.u-over');
              let left = Math.round(uRanger.valToPos(initXmin, 'x'));
              let width = parent.offsetWidth - ( left + 10 );
              let height = (uRanger.bbox.height / devicePixelRatio ) +10;
              uRanger.setSelect({left, width, height, top}, false);

              const sel = uRanger.root.querySelector('.u-select');

              on('mousedown', sel, e => {
                bindMove(e, e => update(lft0 + (e.clientX - x0), wid0));
              });

              on('mousedown', placeDiv(sel, 'u-grip-l'), e => {
                bindMove(e, e => update(lft0 + (e.clientX - x0), wid0 - (e.clientX - x0)));
              });

              on('mousedown', placeDiv(sel, 'u-grip-r'), e => {
                bindMove(e, e => update(lft0, wid0 + (e.clientX - x0)));
              });
            }
          ],
          setSelect: [
            uRanger => {
              zoom(uRanger.select.left, uRanger.select.width);
            }
          ],
        }
      });
    } else {
      _opts = _.merge(_opts, {
        hooks: {
          init: [
            u => {
              u.over.addEventListener('click', () => {
                const idX = u?.cursor?.idx;
                onClick(idX);
              });
            }
          ],
        }
      });
    }

    return {options: _opts, data: finalData};

  }, [data, width, height]);


  const debounce = (fn) => {
    let raf;
    return (...args) => {
      if (raf)
        return;

      raf = requestAnimationFrame(() => {
        fn(...args);
        raf = null;
      });
    };
  };

  const placeDiv = (par, cls) => {
    let el = document.createElement('div');
    el.classList.add(cls);
    par.appendChild(el);
    return el;
  };

  const on = (ev, el, fn) => {
    el && el.addEventListener(ev, fn);
  };

  const off = (ev, el, fn) => {
    el && el.removeEventListener(ev, fn);
  };


  const update = (newLft, newWid) => {
    let newRgt = newLft + newWid;
    let maxRgt = uRanger.current.bbox.width / devicePixelRatio;

    if (newLft >= 0 && newRgt <= maxRgt) {
      select(newLft, newWid, uRanger.current);
    }
  };

  const select = (newLft, newWid) => {
    lftWid.left = newLft;
    lftWid.width = newWid;
    uRanger.current.setSelect(lftWid, false);
  };

  const onClick = (idx) => {
    onClickFunc && onClickFunc(idx);
  };

  const bindMove = (e, onMove) => {
    x0 = e.clientX;
    lft0 = uRanger.current.select.left;
    wid0 = uRanger.current.select.width;

    const _onMove = debounce(onMove);
    on('mousemove', containerRef.current, _onMove);

    const _onUp = () => {
      off('mouseup', containerRef.current, _onUp);
      off('mousemove', containerRef.current, _onMove);
      zoom(uRanger.current.select.left, uRanger.current.select.width);
    };
    on('mouseup', containerRef.current, _onUp);
    e.stopPropagation();
  };

  const zoom =  (newLft, newWid) => {
    let _min = uRanger.current.posToVal(newLft, 'x');
    let _max = uRanger.current.posToVal(newLft + newWid, 'x');
    onZoomFunc &&  onZoomFunc(Math.round(_min), Math.round(_max));
  };

  return (
    <StyledDiv component="div"  ref={containerRef}>
      <UplotReact options={defaultOptions.options} data={defaultOptions.data} onCreate={(chart) => {
        uRanger.current = chart;
      }} />
    </StyledDiv>
  );
}


StackedBars.propTypes = {
  data: PropTypes.object,
  options: PropTypes.object
};

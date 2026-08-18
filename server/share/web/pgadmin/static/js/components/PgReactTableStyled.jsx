/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2025, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////

import React, { forwardRef, useEffect, Fragment } from 'react';
import { flexRender } from '@tanstack/react-table';
import { styled } from '@mui/material/styles';
import PropTypes from 'prop-types';
import KeyboardArrowUpIcon from '@mui/icons-material/KeyboardArrowUp';
import KeyboardArrowDownIcon from '@mui/icons-material/KeyboardArrowDown';
import ChevronRightIcon from '@mui/icons-material/ChevronRight';
import EditRoundedIcon from '@mui/icons-material/EditRounded';
import DeleteRoundedIcon from '@mui/icons-material/DeleteRounded';
import { Checkbox } from '@mui/material';
import LinearProgress, {linearProgressClasses} from '@mui/material/LinearProgress';
import VisibilityIcon from '@mui/icons-material/Visibility';
import CircleIcon from '@mui/icons-material/Circle';
import gettext from 'sources/gettext';
import { PgIconButton } from './Buttons';
import CustomPropTypes from '../custom_prop_types';
import { InputSwitch } from './FormComponents';
import StackBar  from './StackBar';

const StyledLinearProgress = styled(LinearProgress)(({theme, ...props }) => ({
  height: 10,
  borderRadius: 5,
  padding: theme.spacing(0.625),
  width: '100%',
  [`&.${linearProgressClasses.determinate}`]: { backgroundColor: props.firstcolor },
  [`&.${linearProgressClasses.determinate} > .${linearProgressClasses.bar1Determinate}`]: { backgroundColor: props.firstcolor},
}));


// variant prop is used for styling log viewer table in PEM
// variant can be 'logViewer' or '', default is empty string
const StyledDiv = styled('div')(({theme, variant})=>({
  '&.pgrt': {
    display: 'grid',
    overflow: 'auto',
    position: 'relative',
    flexGrow: 1,
  },

  // by default the table has no outer border.
  // the parent container has to take care of border.
  '& .pgrt-table': {
    borderSpacing: 0,
    borderRadius: theme.shape.borderRadius,
    display: 'grid',
    gridAutoRows: 'max-content',
    flexGrow: 1,
    flexDirection: 'column',
    // background color needed for PEM related variants
    ...(variant !== 'logViewer' &&
      variant !== 'dashboardTable' && {
      backgroundColor: theme.palette.background.default,
    }),

    '& .pgrt-header': {
      position: 'sticky',
      top: 0,
      zIndex: 1,

      '&  .pgrt-header-row': {
        // height is not limited for dashboardTable variant
        ...(variant !== 'dashboardTable' && { height: theme.spacing(4.25) }),
        display: 'flex',

        '& .pgrt-header-cell': {
          position: 'relative',
          fontWeight: theme.typography.fontWeightBold,
          // padding is different for dashboardTable variant
          padding:
            variant === 'dashboardTable'
              ? theme.spacing(0.75)
              : theme.spacing(0.5),
          textAlign: 'left',
          alignContent: 'center',
          backgroundColor: theme.palette.background.default,
          overflow: 'hidden',
          ...theme.mixins.panelBorder.bottom,
          borderRight: theme.mixins.panelBorder.bottom.borderBottom,

          '& > div': {
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            textWrap: 'nowrap'
          },
          '& .pgrt-header-cell-content':{
            position: 'relative',
            textAlign: 'left',
            backgroundColor: theme.palette.background.default,
            alignContent: 'center',
          },
          '& .pgrt-header-resizer': {
            display: 'inline-block',
            width: '5px',
            height: '100%',
            position: 'absolute',
            right: 0,
            top: 0,
            transform: 'translateX(50%)',
            zIndex: 1,
            cursor: 'col-resize',
          }
        }
      }
    },

    '& .pgrt-body': {
      position: 'relative',
      flexGrow: 1,
      minHeight: 0,

      '& .pgrt-row': {
        display: 'flex',
        flexDirection: 'column',
        position: 'absolute',
        width: '100%',
        '&:hover': {
          '& .pgrt-row-content': {
            '& .pgrd-row-cell': {
              backgroundColor: theme.otherVars.rowHoverBg,
              '& .MuiCheckbox-root': {
                color: theme.palette.default.main,
              }
            },
          }
        },
        '& .pgrt-row-content': {
          display: 'flex',
          minHeight: 0,

          '& .pgrd-row-cell': {
            margin: 0,
            padding: theme.spacing(0.25, 0.5),
            ...theme.mixins.panelBorder.bottom,
            // PEM related variants has no right border for row cell
            // and height is not limited
            ...(variant !== 'logViewer' &&
              variant !== 'dashboardTable' && {
              ...theme.mixins.panelBorder.right,
              height: theme.spacing(3.75),
            }),
            ...(variant === 'dashboardTable' && {
              padding: theme.spacing(0.75),
            }),
            ...(variant === 'dashboardTable' && {
              padding: theme.spacing(0.75),
            }),
            position: 'relative',
            display: 'flex',
            alignItems: 'flex-start',
            backgroundColor: theme.palette.background.default,

            '&.btn-cell': {
              textAlign: 'center',
            },
            '&.expanded-icon-cell': {
              backgroundColor: theme.palette.grey[400],
              borderBottom: 'none',
            },
            '&.row-warning': {
              backgroundColor: theme.palette.warning.main + '!important'
            },
            '&.row-alert': {
              backgroundColor: theme.palette.error.main + '!important'
            },
            '&.cell-with-icon': {
              paddingLeft: '1.8em',
              borderRadius: 0,
              backgroundPosition: '1%',
            },

            '& .pgrd-row-cell-content': {
              overflow: 'hidden',
              // PEM related variants have word wrap for row cell
              ...((variant === 'logViewer' || variant === 'dashboardTable') && {
                overflowWrap: 'break-word',
                display: 'flex',
                alignItems: 'center',
                height: '100%',
              }),
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
              userSelect: 'text',
              width: '100%',
            },

            '& .reorder-cell': {
              cursor: 'move',
              padding: theme.spacing(0.5, 0.25),
            },
            '& .pgrt-cell-button': {
              border: 0,
              borderRadius: 0,
              padding: 0,
              minWidth: 0,
              backgroundColor: 'inherit',
              '&.Mui-disabled': {
                border: 0,
              },
            }
          }
        },

        '& .pgrt-expanded-content': {
          ...theme.mixins.panelBorder.all,
          margin: theme.spacing(1),
          flexGrow: 1,
        },

        '& .event-type': {
          backgroundColor: theme.palette.grey[600],
          padding: theme.spacing(0.25, 0.75),
          borderRadius: theme.spacing(0.625),
          fontSize: '0.7em',
        },
        '& .query-count': {
          '& > span': {
            paddingRight: theme.spacing(0.75),
            '& > i': {
              paddingRight: theme.spacing(0.75),
            },
          },
        },
        '& .event-type-cell': {
          '& > span': {
            paddingRight: theme.spacing(0.75),
            '& > i': {
              paddingRight: theme.spacing(0.75),
            }
          },
        },
        '& .percentage-cell': {
          'span': {
            width: '100%',
            display: 'inline-flex',
            alignItems: 'center'
          },
        },
      },
    },
  }
}));

export const PgReactTableCell = forwardRef(({row, cell, children, className}, ref)=>{
  let classNames = ['pgrd-row-cell'];
  if (typeof (cell.column.id) == 'string' && cell.column.id.startsWith('btn-')) {
    classNames.push('btn-cell');
  }
  if (cell.column.id == 'btn-edit' && row.getIsExpanded()) {
    classNames.push('expanded-icon-cell');
  }
  if (row.original.row_type === 'warning') {
    classNames.push('row-warning');
  }
  if (row.original.row_type === 'alert') {
    classNames.push('row-alert');
  }
  if(row.original.icon?.[cell.column.id]) {
    classNames.push(row.original.icon[cell.column.id], 'cell-with-icon');
  }
  if(cell.column.columnDef.dataClassName){
    classNames.push(cell.column.columnDef.dataClassName);
  }

  classNames.push(className);

  return (
    <div ref={ref} key={cell.id} style={{
      flex: `var(--col-${cell.column.id.replace(/\W/g, '_')}-size) 0 auto`,
      width: `calc(var(--col-${cell.column.id.replace(/\W/g, '_')}-size)*1px)`,
      ...(cell.column.columnDef.maxSize ? { maxWidth: `${cell.column.columnDef.maxSize}px` } : {})
    }}
    className={classNames.join(' ')}
    title={
      cell.column.columnDef?.disableTooltip
        ? ''
        : String(cell.getValue() ?? '')
    }>
      <div className='pgrd-row-cell-content'>{children}</div>
    </div>
  );
});

PgReactTableCell.displayName = 'PgReactTableCell';
PgReactTableCell.propTypes = {
  row: PropTypes.object,
  cell: PropTypes.object,
  children: CustomPropTypes.children,
  className: PropTypes.any,
};

export const PgReactTableRow = forwardRef(({ children, className, ...props }, ref)=>{
  return (
    <div className={['pgrt-row', className].join(' ')} ref={ref} {...props}>
      {children}
    </div>
  );
});
PgReactTableRow.displayName = 'PgReactTableRow';
PgReactTableRow.propTypes = {
  children: CustomPropTypes.children,
  className: PropTypes.any,
};

export const PgReactTableRowContent = forwardRef(({children, className, ...props}, ref)=>{
  return (
    <div className={['pgrt-row-content', className].join(' ')} ref={ref} {...props}>
      {children}
    </div>
  );
});
PgReactTableRowContent.displayName = 'PgReactTableRowContent';
PgReactTableRowContent.propTypes = {
  children: CustomPropTypes.children,
  className: PropTypes.any,
};


export function PgReactTableRowExpandContent({row, children}) {
  if(!row.getIsExpanded()) {
    return <></>;
  }
  return (
    <div className='pgrt-expanded-content' style={{ maxWidth: 'calc(var(--expand-width)*1px)' }}>
      {children}
    </div>
  );
}
PgReactTableRowExpandContent.propTypes = {
  row: PropTypes.object,
  children: CustomPropTypes.children,
};

export function PgReactTableHeader({table}) {
  return (
    <div className='pgrt-header'>
      {table.getHeaderGroups().map((headerGroup) => (
        <div key={headerGroup.id} className='pgrt-header-row' style={{  }}>
          {headerGroup.headers.map((header) => {
            // Changed for PEM-10. Columns with 'btn-' prefix don't need 'flex'. It causes ColumnGroups to misalign by taking extra space.
            const isFixedWidth = ['btn-selection', 'btn-edit', 'btn-delete', 'btn-reorder']
              .some(suffix => header.id.endsWith(suffix));
            return <div
              key={header.id}
              className='pgrt-header-cell'
              style={{
                ...(isFixedWidth
                  ? { width: `calc(var(--header-${header?.id.replace(/\W/g, '_')}-size)*1px)` }
                  : {
                    flex: `var(--header-${header?.id.replace(/\W/g, '_')}-size) 0 auto`,
                    width: `calc(var(--header-${header?.id.replace(/\W/g, '_')}-size)*1px)`,
                  }),
                ...(header.column.columnDef.maxSize && { maxWidth: `${header.column.columnDef.maxSize}px` }),
              }}
            >
              <div className='pgrt-header-cell-content'>
                <div title={flexRender(header.column.columnDef.header, header.getContext())}
                  style={{cursor: header.column.getCanSort() ? 'pointer' : 'initial'}}

                  onClick={header.column.getCanSort() ? header.column.getToggleSortingHandler() : undefined}
                >
                  {flexRender(header.column.columnDef.header, header.getContext())}
                  {header.column.getCanSort() && header.column.getIsSorted() &&
                  <span>
                    {header.column.getIsSorted() == 'desc' ?
                      <KeyboardArrowDownIcon style={{ fontSize: '1.2rem' }} />
                      : <KeyboardArrowUpIcon style={{ fontSize: '1.2rem' }} />}
                  </span>}
                </div>
                {header.column.getCanResize() && (
                  <div
                    onDoubleClick={() => header.column.resetSize()}
                    onMouseDown={header.getResizeHandler()}
                    onTouchStart={header.getResizeHandler()}
                    className='pgrt-header-resizer'
                  />
                )}
              </div>
            </div>;
          })}
        </div>
      ))}
    </div>
  );
}
PgReactTableHeader.propTypes = {
  table: PropTypes.object,
};

export function PgReactTableBody({children, style}) {
  return (
    <div className='pgrt-body' style={style}>
      {children}
    </div>
  );
}
PgReactTableBody.propTypes = {
  style: PropTypes.object,
  children: CustomPropTypes.children,
};

export const PgReactTable = forwardRef(({children, table, rootClassName, tableClassName, onScrollFunc, ...props}, ref)=>{
  const columns = table.getAllColumns();

  useEffect(()=>{
    const setMaxExpandWidth = ()=>{
      if(ref.current) {
        ref.current.style['--expand-width'] = (ref.current.getBoundingClientRect().width ?? 430) - 30; //margin,scrollbar,etc.
      }
    };
    const tableResizeObserver = new ResizeObserver(()=>{
      setMaxExpandWidth();
    });
    tableResizeObserver.observe(ref.current);
  }, []);

  const columnSizeVars = React.useMemo(() => {
    const headers = table.getFlatHeaders();
    const colSizes = {};
    for (let value of headers) {
      const header = value;
      colSizes[`--header-${header.id.replace(/\W/g, '_')}-size`] = header.getSize();
      colSizes[`--col-${header.column.id.replace(/\W/g, '_')}-size`] = header.column.getSize();
    }
    return colSizes;
  }, [columns, table.getState().columnSizingInfo]);

  return (
    // variant prop is used for styling log viewer table in PEM
    <StyledDiv className={['pgrt', rootClassName].join(' ')} ref={ref} onScroll={e => onScrollFunc?.(e.target)} variant={props.variant}>
      <div className={['pgrt-table', tableClassName].join(' ')} style={{ ...columnSizeVars }} {...props}>
        {children}
      </div>
    </StyledDiv>
  );
});
PgReactTable.displayName = 'PgReactTable';
PgReactTable.propTypes = {
  table: PropTypes.object,
  rootClassName: PropTypes.any,
  tableClassName: PropTypes.any,
  children: CustomPropTypes.children,
  onScrollFunc: PropTypes.any,
  variant: PropTypes.string,
};

export function getExpandCell({ onClick, title }) {
  const Cell = ({ row }) => {
    const onClickFinal = (e) => {
      e.preventDefault();
      row.toggleExpanded();
      onClick?.(row, e);
    };
    return (
      <PgIconButton
        size="xs"
        icon={
          row.getIsExpanded() ? (
            <KeyboardArrowDownIcon />
          ) : (
            <ChevronRightIcon />
          )
        }
        noBorder
        onClick={onClickFinal}
        aria-label={title}
      />
    );
  };

  Cell.displayName = 'ExpandCell';
  Cell.propTypes = {
    row: PropTypes.any,
  };

  return Cell;
}

export function getSwitchCell() {
  const Cell = ({ getValue }) => {
    return <InputSwitch value={getValue()} readOnly />;
  };

  Cell.displayName = 'SwitchCell';
  Cell.propTypes = {
    cell: PropTypes.any,
    getValue: PropTypes.func,
  };

  return Cell;
}

export function getCheckboxCell({title}) {
  const Cell = ({ table }) => {
    return (
      <div style={{textAlign: 'center', minWidth: 20}}>
        <Checkbox
          color="primary"
          checked={table.getIsAllRowsSelected()}
          indeterminate={table.getIsSomeRowsSelected()}
          onChange={table.getToggleAllRowsSelectedHandler()}
          slotProps={{input: { 'aria-label': title }}}
        />
      </div>
    );
  };

  Cell.displayName = 'CheckboxCell';
  Cell.propTypes = {
    table: PropTypes.object,
  };

  return Cell;
}

export function getCheckboxHeaderCell({title}) {
  const Cell = ({ row }) => {
    return (
      <div style={{textAlign: 'center', minWidth: 20}}>
        <Checkbox
          color="primary"
          checked={row.getIsSelected()}
          indeterminate={row.getIsSomeSelected()}
          disabled={!row.getCanSelect()}
          onChange={row.getToggleSelectedHandler()}
          slotProps={{input: { 'aria-label': title}}}
        />
      </div>
    );
  };

  Cell.displayName = 'CheckboxHeaderCell';
  Cell.propTypes = {
    row: PropTypes.object,
  };

  return Cell;
}

export function getEditCell({isDisabled, title, onClick, onEdit}) {
  const Cell = ({ row }) => {
    return <PgIconButton data-test="expand-row" title={title} icon={<EditRoundedIcon fontSize="small" />} className='pgrt-cell-button'
      onClick={()=>{
        if(onEdit) onEdit(row);
        else onClick ? onClick(row) : row.toggleExpanded();
      }} disabled={isDisabled?.(row)}
    />;
  };

  Cell.displayName = 'EditCell';
  Cell.propTypes = {
    row: PropTypes.any,
  };

  return Cell;
}

export function getDeleteCell({isDisabled, title, onClick}) {
  const Cell = ({ row }) => (
    <PgIconButton data-test="delete-row" title={title} icon={<DeleteRoundedIcon fontSize="small" />}
      onClick={()=>onClick?.(row)}
      className='pgrt-cell-button' disabled={isDisabled?.(row)}
    />
  );

  Cell.displayName = 'DeleteCell';
  Cell.propTypes = {
    row: PropTypes.any,
  };

  return Cell;
}


export function getViewCell({sampleTime, onClick, pgAdmin}) {
  const Cell = ({ row, column }) => (

    <PgIconButton
      size="xs"
      noBorder
      icon={<VisibilityIcon />}
      className='Dashboard-visibilityButton'
      onClick={() => {
        onClick?.(row, column, sampleTime, pgAdmin);
      }}
      aria-label={gettext('View')}
    />
  );

  Cell.displayName = 'ViewCell';
  Cell.propTypes = {
    row: PropTypes.any,
    column: PropTypes.any,
  };

  return Cell;
};


export function getPercentageCell({firstName, firstValue, firstPercentage, secondPercentage, firstColor,
  secondName, secondValue, secondColor, showProgressbar=true, showInfo=false, showPercentage=false, colorCodeMappings=[]}) {
  const Cell = ({ row }) => {
    let data = [{
      percentage: row.original[firstPercentage],
      color: colorCodeMappings[firstColor],
      leftRadius: true,
      rightRadius: parseFloat(row.original[firstPercentage]) == 100 ? true : false,
      tooltip: firstName + ': ' + row.original[firstValue]  + '/' +  (row.original[firstValue] + row.original[secondValue]) + ' (' + row.original[firstPercentage] + '% )',
    }, {
      percentage: row.original[secondPercentage],
      color: colorCodeMappings[secondColor],
      leftRadius: false,
      rightRadius: true,
      tooltip: secondName + ': ' + row.original[secondValue]  + '/' +  (row.original[firstValue] + row.original[secondValue]) + ' (' + row.original[secondPercentage] + '% )',

    }];

    return (<>
      {showProgressbar && <span className='percentage-cell'> <StackBar data={data} />
       ({row.original[firstPercentage]} %)</span>}
      {!showProgressbar && showInfo && `${row.original[firstValue]} / ${row.original[firstValue] + row.original[secondValue]}`}
      {!showProgressbar && showPercentage && `${row.original[firstPercentage]}`}</>
    );
  };

  Cell.displayName = 'percentageCell';
  Cell.propTypes = {
    row: PropTypes.any,
  };

  return Cell;
}

export function getEventWaitCell() {

  const Cell = ({ cell }) => {
    let data = cell.getValue(),
      totalVal = 0,
      colorMap = cell.column.columnDef.options.colorCodeMappings;

    for(let i = 0; i < data.length; ++i) {
      if (data[i].wait_event) {
        totalVal += data[i].count;
      }
    }

    let cnt = 0;
    for(let i = 0; i < data.length; ++i) {
      data[i].color = '';
      if (data[i].wait_event) {
        data[i].percentage = (data[i].count * 100 / totalVal).toFixed(2);
        data[i].color = colorMap[data[i].wait_event_type];
        data[i].leftRadius = cnt == 0 ? true : false;
        data[i].rightRadius = i == data.length -1 ? true : false;
        data[i].tooltip = (<>
          <div>{gettext('Wait event type:')} {data[i]['wait_event_type']}</div>
          <div>{gettext('Wait event:')} {data[i]['wait_event']}</div>
          <div>{gettext('Count:')} {data[i]['count']} ({data[i]['percentage']}%)</div> </>);
        cnt = cnt + 1;
      } else {
        data[i].percentage = 0;
      }
    }
    return <StackBar data={data} />;
  };

  Cell.displayName = 'EventWaitCell';
  Cell.propTypes = {
    cell: PropTypes.any,
  };

  return Cell;
}


export function getStackCell() {

  const getStackValues = (col, values) => {
    let stacks = [];
    let colorCodeMappings = col.options.colorCodeMappings;
    let tooltipFunc =
        _.isFunction(col.options.tooltipField) ? col.options.tooltipField : (val) => (val[col.options.tooltipField]);
    let colorCodeFunc =
        _.isFunction(col.options.colorCodeField) ? col.options.colorCodeField : (val) => (colorCodeMappings[val[col.options.colorCodeField]]);

    let cnt = 0;
    _.each(values, function(value) {
      let _tooltip = (<div> {gettext('Wait type:')} {tooltipFunc(value, col.options)} <br/>  {gettext('Wait count:')}   {value[col.options.valueField]}</div>);
      if (col.options.max) {
        stacks.push({
          'value': value[col.options.valueField],
          'percentage': (value[col.options.valueField] * 100) / col.options.max,
          'color': colorCodeFunc(value),
          'data': value,
          'leftRadius': cnt == 0 ? true : false,
          'rightRadius': cnt == values.length -1 ? true : false,
          'tooltip': _tooltip,
        });
      } else if(col.options.individualRowCalculationField) {
        stacks.push({
          'value': value[col.options.valueField],
          'percentage': (value[col.options.valueField] * 100) / self.model.get(col.options.individualRowCalculationField),
          'color': colorCodeFunc(value),
          'data': value,
          'leftRadius': cnt == 0 ? true : false,
          'rightRadius': cnt == values.length -1 ? true : false,
          'tooltip': _tooltip,
        });
      } else {
        stacks.push({
          'value': value[col.options.valueField],
          'percentage': value[col.options.valueField],
          'color': colorCodeFunc(value),
          'data': value,
          'leftRadius': cnt == 0 ? true : false,
          'rightRadius': cnt == values.length -1 ? true : false,
          'tooltip': _tooltip,
        });
      }
      cnt = cnt +1;
    });

    return stacks;
  };

  const Cell = ({ cell }) => {
    let _col =   cell.column.columnDef;
    _col.options.max = cell.getContext().table.getRow(0).original[_col.options.maxField];

    let data = getStackValues(_col, cell.getValue());

    return <StackBar data={data} />;
  };


  Cell.displayName = 'StackCell';
  Cell.propTypes = {
    cell: PropTypes.any,
  };

  return Cell;

}


export function getQueryCountCell() {
  const Cell = ({ row }) => {
    let data = row.original;

    return (
      <div className='query-count'><span><i className='fa fa-terminal'></i>{data?.cpu_count}</span>
        <span><i className='fa fa-user'></i>{data?.users_count}</span>
        <span><i className='fa fa-database'></i>{data?.databases_count}</span>
      </div>
    );
  };

  Cell.displayName = 'QueryCountCell';
  Cell.propTypes = {
    row: PropTypes.any,
  };
  return Cell;
}

export function getQueryDashboardEventCell({typeIcon=true}) {
  const Cell = ({ row }) => {
    let data = row.original;

    return (
      <div className='event-type-cell'>
        {typeIcon && <span><CircleIcon fontSize="0.3em"  sx={{ color: data.color }}/></span>}
        <span>{data?.event}</span>
        <span className='event-type'>{data?.type}</span>
      </div>
    );
  };

  Cell.displayName = 'QueryDashboardEventCell';
  Cell.propTypes = {
    row: PropTypes.any,
  };
  return Cell;
}



export function getLinearProgressCell() {
  const Cell = ({ cell, getValue }) => {
    return (
      <span className='percentage-cell'>
        <StyledLinearProgress value={getValue()}  firstcolor={cell.row.original.color} variant="determinate" readOnly />
      </span>
    );
  };

  Cell.displayName = 'LinearProgressCell';
  Cell.propTypes = {
    cell: PropTypes.any,
    getValue: PropTypes.func,
  };

  return Cell;
}


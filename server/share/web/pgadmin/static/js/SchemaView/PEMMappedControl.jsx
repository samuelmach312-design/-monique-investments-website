///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import PropTypes from 'prop-types';


class Registry {
  static _cells = {};
  static _controls = {};

  static registerCellControl(cellType, customCellFunc) {
    if (cellType in Registry._cells) {
      throw new Error(
        `Custom cell control '${cellType}' is alredy registered.`
      );
    }
    if (typeof customCellFunc !== 'function') {
      throw new Error(
        `Custom cell control '${cellType}' did not provide a valid render function.`
      );
    }
    Registry._cells[cellType] = customCellFunc;
  }

  static renderCellControl({cell, value, ...props}) {
    if (cell in Registry._cells) {
      return Registry._cells[cell]({cell, value, ...props});
    }
    return null;
  }

  static registerFormControl(controlType, customControlFunc) {
    if (controlType in Registry._controls) {
      throw new Error(
        `Custom form control '${controlType}' is alredy registered.`
      );
    }
    if (typeof customControlFunc !== 'function') {
      throw new Error(
        `Custom form control '${controlType}' did not provide a valid render function.`
      );
    }
    Registry._controls[controlType] = customControlFunc;
  }

  static renderFormControl({type, ...props}) {
    if (type in Registry._controls) {
      return Registry._controls[type]({type, ...props});
    }
    return null;
  }
}

export const register_pem_custom_cell = (cellType, customCellFunc) => {
  Registry.registerCellControl(cellType, customCellFunc);
};

export function PEMMappedCellControl({cell, ...props}) {
  return Registry.renderCellControl({cell, ...props});
}

PEMMappedCellControl.propTypes = {
  cell: PropTypes.oneOfType([PropTypes.string, PropTypes.number]).isRequired,
  props: PropTypes.object,
};

export const register_pem_custom_control = (controlType, customControlFunc) => {
  Registry.registerFormControl(controlType, customControlFunc);
};

export function PEMMappedFormControl({type, ...props}) {
  return Registry.renderFormControl({type, ...props});
}

PEMMappedFormControl.propTypes = {
  type: PropTypes.oneOfType([PropTypes.string, PropTypes.number]).isRequired,
  props: PropTypes.object,
};

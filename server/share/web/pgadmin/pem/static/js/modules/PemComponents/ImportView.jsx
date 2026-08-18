///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState } from 'react';
import PropTypes from 'prop-types';
import {
  FormControlLabel,
  Typography,
  Box,
  TableContainer,
  Paper,
} from '@mui/material';
import { styled } from '@mui/system';
import DriveFileMoveIcon from '@mui/icons-material/DriveFileMove';
import CloseIcon from '@mui/icons-material/Close';
import CloseRoundedIcon from '@mui/icons-material/CloseRounded';
import DoneRoundedIcon from '@mui/icons-material/DoneRounded';
import InfoRoundedIcon from '@mui/icons-material/InfoRounded';

import pgAdmin from 'sources/pgadmin';
import gettext from 'sources/gettext';
import PgTable from 'sources/components/PgTable';
import getApiInstance from 'sources/api_instance';
import { PrimaryButton } from 'sources/components/Buttons';
import { DefaultButton } from 'sources/components/Buttons';
import { StyledBox } from 'sources/SchemaView/StyledComponents';
import { FormInput, InputCheckbox } from 'sources/components/FormComponents';
import { STATUSES } from 'pem/common/constants';

import CustomFileInput from './CustomFileInput';

const StyledInnerBox = styled(Box)(({ theme }) => ({
  padding: theme.spacing(2),
}));

const StyledTypography = styled(Typography)(() => ({
  fontWeight: 'bold',
}));

const StyledTableContainer = styled(TableContainer)(({ theme }) => ({
  boxShadow: 'none',
  marginTop: theme.spacing(1),
}));

const StyledFormControlLabel = styled(FormControlLabel)(({ theme }) => ({
  margin: theme.spacing(0.5),
}));

const SummaryContainer = styled(Box)(({ theme }) => ({
  marginTop: theme.spacing(2),
  padding: theme.spacing(2),
  borderRadius: theme.spacing(1),
  backgroundColor: theme.palette.default.main,
  border: `1px solid ${theme.palette.default.borderColor}`,
}));

const STATUS_ICON = {
  [STATUSES.FAILED]: <CloseRoundedIcon style={{ color: 'red' }} />,
  [STATUSES.SUCCESS]: <DoneRoundedIcon style={{ color: 'green' }} />,
  [STATUSES.SKIPPED]: <InfoRoundedIcon style={{ color: 'orange' }} />,
};

const ImportView = ({
  closeDialog,
  url,
  successMsg,
  view,
  dataDispatch,
  schemaState,
  allowedFileType
}) => {
  const [selectedFile, setSelectedFile] = useState(null);
  const [skipExisting, setSkipExisting] = useState(true);
  const [skipExistingDependantProbe, setSkipExistingDependantProbe] =
    useState(true);
  const [importSummary, setImportSummary] = useState([]);
  const [isValid, setIsValid] = useState(true);
  const [content, setContent] = useState([]);
  const columns = [
    {
      accessorKey: 'status',
      header: 'Status',
      cell: ({ getValue }) => <div>{STATUS_ICON[getValue()]}</div>,
      enableSorting: true,
      enableResizing: true,
      enableFilters: true,
      disableTooltip: false,
      size: 150,
    },
    {
      accessorKey: 'description',
      header: 'Description',
      enableSorting: true,
      enableResizing: true,
      enableFilters: true,
      disableTooltip: false,
      size: 150,
    },
  ];
  const handleFileChange = (event) => {
    event.preventDefault();
    const uploadedFile = event.target.files[0];
    setSelectedFile(uploadedFile);
    if (uploadedFile) {
      const readFile = new FileReader();

      readFile.onload = (e) => {
        const contents = e.target.result;

        try {
          const json = JSON.parse(contents);
          setIsValid(true);
          setContent(json);
        } catch {
          setIsValid(false);
          setContent(null);
          pgAdmin.Browser.notifier.error(
            gettext('File contains invalid JSON data')
          );
        }
      };

      readFile.readAsText(uploadedFile);
    } else {
      setContent(null);
      setIsValid(false);
    }
  };

  const handleImportSummary = (data) => {
    const objType = view;
    setImportSummary(
      data.map(({ status, name, msg }) => ({
        status,
        description:
          status === STATUSES.FAILED
            ? gettext(`The ${objType} '${name || ''}' failed`) +
              (msg ? `: ${msg.toLowerCase()}` : '')
            : status === STATUSES.SKIPPED
              ? gettext(`The ${objType} '${name}' was skipped`)
              : gettext(`The ${objType} '${name}' was imported successfully`),
      }))
    );
  };

  const handleImport = async () => {
    if (!selectedFile) {
      pgAdmin.Browser.notifier.error(
        gettext('Please select a file to import.')
      );
      return;
    }
    setImportSummary([]);

    try {
      const api = getApiInstance();
      api
        .post(url, {
          content: content,
          skip_overwrite: skipExisting,
          skip_overwrite_probe: skipExistingDependantProbe,
          valid: isValid,
        })
        .then((res) => {
          handleImportSummary(res.data.result);
          pgAdmin.Browser.notifier.success(successMsg);
        })
        .then(() => {
          schemaState.initialise(dataDispatch, true);
        })
        .catch((err) => {
          pgAdmin.Browser.notifier.pgNotifier('error-noalert', err, '');
        });
    } catch {
      setImportSummary([
        { status: 'error', description: 'An error occurred during import.' },
      ]);
    }
  };
  return (
    <StyledBox>
      <StyledInnerBox className="Properties-form">
        <FormInput required={true} label={gettext('Select file')} error={false}>
          <CustomFileInput
            type="file"
            onFileChange={handleFileChange}
            allowedExtension={allowedFileType}
          />
        </FormInput>
        <StyledFormControlLabel
          control={
            <InputCheckbox
              checked={skipExisting}
              onChange={(e) => setSkipExisting(e.target.checked)}
              color="primary"
            />
          }
          label={gettext('Skip existing?')}
        />
        {(view === 'Alert Templates' || view === 'Manage Charts') && (
          <>
            <br />
            <StyledFormControlLabel
              control={
                <InputCheckbox
                  checked={skipExistingDependantProbe}
                  onChange={(e) =>
                    setSkipExistingDependantProbe(e.target.checked)
                  }
                  color="primary"
                />
              }
              label={gettext('Skip existing dependent probes?')}
            />
          </>
        )}
        <SummaryContainer>
          <StyledTypography variant="h6">
            {gettext('Import Summary')}
          </StyledTypography>
          <StyledTableContainer component={Paper}>
            <PgTable
              caveTable={false}
              columns={columns}
              type="panel"
              data={importSummary || []}
              showSearch={false}
              tableNoBorder={false}
              variant="dashboardTable"
            />
          </StyledTableContainer>
        </SummaryContainer>
      </StyledInnerBox>
      <Box className="Dialog-footer">
        <Box marginLeft="auto">
          <DefaultButton
            data-test="Close"
            onClick={closeDialog}
            startIcon={<CloseIcon />}
            className="Dialog-buttonMargin"
          >
            {gettext('Close')}
          </DefaultButton>
          <PrimaryButton
            onClick={handleImport}
            startIcon={<DriveFileMoveIcon />}
            label={gettext('Import')}
            disabled={!selectedFile}
          >
            {gettext('Import')}
          </PrimaryButton>
        </Box>
      </Box>
    </StyledBox>
  );
};

ImportView.propTypes = {
  closeDialog: PropTypes.func.isRequired,
  url: PropTypes.string.isRequired,
  successMsg: PropTypes.string.isRequired,
  view: PropTypes.string.isRequired,
  dataDispatch: PropTypes.func.isRequired,
  schemaState: PropTypes.object.isRequired,
  allowedFileType: PropTypes.string
};

export default ImportView;

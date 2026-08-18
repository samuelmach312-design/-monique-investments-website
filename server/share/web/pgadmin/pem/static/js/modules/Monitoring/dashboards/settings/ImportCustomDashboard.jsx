///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState } from 'react';
import PropTypes from 'prop-types';
import FormControlLabel from '@mui/material/FormControlLabel';
import Typography from '@mui/material/Typography';
import Box from '@mui/material/Box';
import Table from '@mui/material/Table';
import TableBody from '@mui/material/TableBody';
import TableCell from '@mui/material/TableCell';
import TableContainer from '@mui/material/TableContainer';
import TableHead from '@mui/material/TableHead';
import TableRow from '@mui/material/TableRow';
import Paper from '@mui/material/Paper';
import { styled } from '@mui/system';
import DriveFileMoveIcon from '@mui/icons-material/DriveFileMove';
import CloseIcon from '@mui/icons-material/Close';
import CloseRoundedIcon from '@mui/icons-material/CloseRounded';
import DoneRoundedIcon from '@mui/icons-material/DoneRounded';
import InfoRoundedIcon from '@mui/icons-material/InfoRounded';

import pgAdmin from 'sources/pgadmin';
import gettext from 'sources/gettext';
import getApiInstance from 'sources/api_instance';
import { DefaultButton } from 'sources/components/Buttons';
import { StyledBox } from 'sources/SchemaView/StyledComponents';
import { FormInput, InputCheckbox } from 'sources/components/FormComponents';
import { STATUSES } from 'pem/common/constants';
import { NODE_LEVEL_CONSTANTS } from 'pem/modules/Monitoring/Common/constants';
import CustomFileInput from '../../../PemComponents/CustomFileInput';

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

const StyledTableCellHeader = styled(TableCell)(({ theme }) => ({
  fontWeight: 'bold',
  color: theme.palette.default.contrastText,
}));

const StyledTableCell = styled(TableCell)(({ theme }) => ({
  marginLeft: theme.spacing(12.5),
  padding: theme.spacing(1),
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

const ImportCustomDashboard = ({ closeDialog, url, refreshDashboard }) => {
  const [selectedFile, setSelectedFile] = useState(null);
  const [skipExisting, setSkipExisting] = useState(true);
  const [skipExistingDependantCharts, setSkipExistingDependantCharts] =
    useState(true);
  const [skipExistingDependantProbe, setSkipExistingDependantProbe] =
    useState(true);
  const [importSummary, setImportSummary] = useState([]);
  const [isValid, setIsValid] = useState(true);
  const [content, setContent] = useState([]);

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

  const getDescription = (data, level) => {
    let description = '';

    switch (data.status) {
    case STATUSES.FAILED:
      description =
          gettext(`The dashboard '${data.name || ''}' failed`) +
          (data.msg ? `: ${data.msg.toLowerCase()}` : '');
      pgAdmin.Browser.notifier.error(gettext('Failed to import'));
      return description;
    case STATUSES.SKIPPED:
      description = gettext(
        `The ${NODE_LEVEL_CONSTANTS[level].TYPE.toLowerCase()} dashboard '${
          data.name
        }' was skipped`
      );
      pgAdmin.Browser.notifier.info(gettext('Import was skipped'));
      return description;
    default:
      refreshDashboard();
      description = gettext(
        `The ${NODE_LEVEL_CONSTANTS[level].TYPE.toLowerCase()} dashboard '${
          data.name
        }' was imported successfully`
      );
      pgAdmin.Browser.notifier.success(gettext('Successfully imported'));
      return description;
    }
  };

  const handleImportSummary = (data, level) => {
    setImportSummary([
      {
        status: data[0].status,
        description: getDescription(data[0], level),
      },
    ]);
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
          skip_overwrite_chart: skipExistingDependantCharts,
          skip_overwrite_probe: skipExistingDependantProbe,
          valid: isValid,
        })
        .then((res) => {
          handleImportSummary(res.data.result, content.dashboards[0].level);
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
      <StyledInnerBox className='Properties-form'>
        <FormInput required={true} label={gettext('Select file')} error={false}>
          <CustomFileInput onFileChange={handleFileChange} accept='.pemdash' />
        </FormInput>
        <StyledFormControlLabel
          control={
            <InputCheckbox
              checked={skipExisting}
              onChange={(e) => setSkipExisting(e.target.checked)}
              color='primary'
            />
          }
          label={gettext('Skip existing?')}
        />
        <>
          <br />
          <StyledFormControlLabel
            control={
              <InputCheckbox
                checked={skipExistingDependantCharts}
                onChange={(e) =>
                  setSkipExistingDependantCharts(e.target.checked)
                }
                color='primary'
              />
            }
            label={gettext('Skip existing dependent charts?')}
          />
        </>
        <>
          <br />
          <StyledFormControlLabel
            control={
              <InputCheckbox
                checked={skipExistingDependantProbe}
                onChange={(e) =>
                  setSkipExistingDependantProbe(e.target.checked)
                }
                color='primary'
              />
            }
            label={gettext('Skip existing dependent probes?')}
          />
        </>
        <SummaryContainer>
          <StyledTypography variant='h6'>
            {gettext('Import Summary')}
          </StyledTypography>
          <StyledTableContainer component={Paper}>
            <Table>
              <TableHead>
                <TableRow>
                  <StyledTableCellHeader>
                    {gettext('Status')}
                  </StyledTableCellHeader>
                  <StyledTableCellHeader>
                    {gettext('Description')}
                  </StyledTableCellHeader>
                </TableRow>
              </TableHead>
              <TableBody>
                {importSummary.map((item, index) => (
                  <TableRow key={index}>
                    <StyledTableCell>
                      {STATUS_ICON[item.status]}
                    </StyledTableCell>
                    <StyledTableCell>{item.description}</StyledTableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </StyledTableContainer>
        </SummaryContainer>
      </StyledInnerBox>
      <Box className='Dialog-footer'>
        <Box marginLeft='auto'>
          <DefaultButton
            data-test='Close'
            onClick={() => {
              closeDialog();
            }}
            startIcon={<CloseIcon />}
            className='Dialog-buttonMargin'
          >
            {gettext('Close')}
          </DefaultButton>
          <DefaultButton
            onClick={handleImport}
            startIcon={<DriveFileMoveIcon />}
            label={gettext('Import')}
            disabled={false}
          >
            {gettext('Import')}
          </DefaultButton>
        </Box>
      </Box>
    </StyledBox>
  );
};

ImportCustomDashboard.propTypes = {
  closeDialog: PropTypes.func.isRequired,
  url: PropTypes.string.isRequired,
  refreshDashboard: PropTypes.func.isRequired,
};

export default ImportCustomDashboard;

import React, { useRef, useState } from 'react';
import PropTypes from 'prop-types';
import { styled } from '@mui/system';
import Button from '@mui/material/Button';

import gettext from 'sources/gettext';

const FileInputWrapper = styled('div')(({ theme }) => ({
  display: 'flex',
  alignItems: 'center',
  padding: theme.spacing(0.625, 1.25),
  border: `0.5px solid ${theme.palette.default.borderColor}`,
  borderRadius: theme.spacing(0.5),
  backgroundColor: theme.otherVars.editor.guttersBg,
  cursor: 'pointer',
  width: '100%',
  fontSize: theme.spacing(1.75),
  color: theme.palette.text.primary,
}));

const ChooseFileButton = styled(Button)(({ theme }) => ({
  padding: theme.spacing(0.625, 1.25),
  border: `1px solid ${theme.palette.default.borderColor}`,
  borderRadius: theme.spacing(0.5),
  backgroundColor: theme.palette.default.main,
  color: theme.palette.text.primary,
  textTransform: 'none',
  fontSize: theme.spacing(1.75),
  marginRight: theme.spacing(1.25),
}));

const HiddenFileInput = styled('input')({
  display: 'none',
});

const CustomFileInput = ({ onFileChange, allowedExtension = '' }) => {
  const fileInputRef = useRef(null);
  const [fileName, setFileName] = useState('');

  const handleButtonClick = () => {
    fileInputRef.current.click();
  };

  const handleFileChange = (event) => {
    const file = event.target.files[0];
    if (file) {
      setFileName(file.name);
      if (onFileChange) onFileChange(event);
    }
  };

  const accept = allowedExtension.startsWith('.')
    ? allowedExtension
    : `.${allowedExtension}`;
  return (
    <FileInputWrapper onClick={handleButtonClick}>
      <ChooseFileButton
        variant="outlined"
        onClick={(event) => {
          event.stopPropagation();
          handleButtonClick();
        }}
      >
        {gettext('Choose File')}
      </ChooseFileButton>
      <span>{fileName || gettext('No file chosen')}</span>
      <HiddenFileInput
        type="file"
        data-testid="file-input"
        ref={fileInputRef}
        onChange={handleFileChange}
        accept={accept}
      />
    </FileInputWrapper>
  );
};

CustomFileInput.propTypes = {
  onFileChange: PropTypes.func.isRequired,
  allowedExtension: PropTypes.string,
};

export default CustomFileInput;

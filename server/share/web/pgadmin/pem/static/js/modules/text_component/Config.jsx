///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState, useEffect } from 'react';
import PropTypes from 'prop-types';
import getApiInstance from 'sources/api_instance';
import url_for from 'sources/url_for';
import gettext from 'sources/gettext';
import {
  StyledErrorDiv,
  StyledTextInfo,
} from 'pem/modules/text_component/common/styledComponents';
import { StyledWarningIcon, StyledInfoIcon } from 'pem/common/StyledComponents';
import { generateRandomNumber, handleError } from 'pem/common/utils';

const TextComponent = ({ did, trans_id, cid, aid }) => {
  const [textInfo, setTextInfo] = useState('');
  const [error, setError] = useState({ errorMessage: '', serverError: false });
  const api = getApiInstance();
  const handleFetch = () => {
    api
      .get(
        url_for('charts.agent_text_data', {
          did,
          trans_id,
          cid,
          aid,
        })
      )
      .then((res) => {
        setTextInfo(res?.data?.data?.html.replace(/&#183;/g, '·'));
        setError('');
      })
      .catch((errorResponse) => {
        handleError(errorResponse, { did, cid, aid }, setError);
      });
  };

  useEffect(() => {
    handleFetch();
  }, []);

  return (
    <StyledTextInfo
      data-testid='text-component'
      id={`text_component${generateRandomNumber()}`}
      aria-label='Text information'
    >
      {error.errorMessage ? (
        <StyledErrorDiv serverError={error?.serverError}>
          {error?.serverError ? <StyledWarningIcon /> : <StyledInfoIcon />}
          {'  '}
          {error?.errorMessage}
        </StyledErrorDiv>
      ) : (
        gettext(textInfo)
      )}
    </StyledTextInfo>
  );
};

TextComponent.propTypes = {
  did: PropTypes.number.isRequired,
  trans_id: PropTypes.number.isRequired,
  cid: PropTypes.number.isRequired,
  aid: PropTypes.number,
};

export default TextComponent;

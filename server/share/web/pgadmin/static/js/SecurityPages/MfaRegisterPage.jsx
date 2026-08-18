/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2025, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////
import { Box } from '@mui/material';
import React, { useState } from 'react';
import LoginImage from '../../img/login.svg?svgr';
import { FormNote, InputText } from '../components/FormComponents';
import BasePage, { SecurityButton, SecurityAuthIcon } from './BasePage';
import { DefaultButton } from '../components/Buttons';
import gettext from 'sources/gettext';
import PropTypes from 'prop-types';

function EmailRegisterView({ mfaView, onValidityChange }) {
  const [inputEmail, setInputEmail] = useState(mfaView.email_address || '');
  const [inputCode, setInputCode] = useState('');

  // Validate whenever state changes
  React.useEffect(() => {
    if (mfaView.email_address_placeholder) {
      onValidityChange(!!inputEmail);
    } else if (mfaView.otp_placeholder) {
      onValidityChange(!!inputCode);
    } else {
      onValidityChange(false);
    }
  }, [inputEmail, inputCode, mfaView, onValidityChange]);

  if (mfaView.email_address_placeholder) {
    return <>
      <div style={{textAlign: 'center', fontSize: '1.2em'}} data-test="email-register-view">{mfaView.label}</div>
      <div>
        <input type='hidden' name={mfaView.auth_method} value='SETUP'/>
        <input type='hidden' name='validate' value='send_code'/>
      </div>
      <div>{mfaView.description}</div>
      <InputText value={inputEmail} type="email" name="send_to" placeholder={mfaView.email_address_placeholder}
        onChange={setInputEmail} required
      />
      <FormNote text={mfaView.note} />
    </>;
  } else if (mfaView.otp_placeholder) {
    return <>
      <div style={{textAlign: 'center', fontSize: '1.2em'}} data-test="email-register-view">{mfaView.label}</div>
      <div>
        <input type='hidden' name={mfaView.auth_method} value='SETUP'/>
        <input type='hidden' name='validate' value='verify_code'/>
      </div>
      <div>{mfaView.message}</div>
      <InputText value={inputCode} pattern="\d{6}" type="password" name="code" placeholder={mfaView.otp_placeholder}
        onChange={setInputCode} required autoComplete="one-time-code"
      />
    </>;
  }
  return null;
}

EmailRegisterView.propTypes = {
  mfaView: PropTypes.object,
  onValidityChange: PropTypes.func.isRequired,
};

function AuthenticatorRegisterView({ mfaView, onValidityChange }) {
  const [inputValue, setInputValue] = useState('');

  React.useEffect(() => {
    onValidityChange(!!inputValue);
  }, [inputValue, onValidityChange]);

  return <>
    <div style={{textAlign: 'center', fontSize: '1.2em'}} data-test="auth-register-view">{mfaView.auth_title}</div>
    <div>
      <input type='hidden' name={mfaView.auth_method} value='SETUP'/>
      <input type='hidden' name='VALIDATE' value='validate'/>
    </div>
    <div style={{minHeight: 0, display: 'flex'}}>
      <img src={`data:image/jpeg;base64,${mfaView.image}`} style={{maxWidth: '100%', objectFit: 'contain'}} alt={mfaView.qrcode_alt_text} />
    </div>
    <div>{mfaView.auth_description}</div>
    <InputText value={inputValue} type="password" name="code" placeholder={mfaView.otp_placeholder}
      onChange={setInputValue}
    />
  </>;
}

AuthenticatorRegisterView.propTypes = {
  mfaView: PropTypes.object,
  onValidityChange: PropTypes.func.isRequired,
};

export default function MfaRegisterPage({ actionUrl, mfaList, nextUrl, mfaView, ...props }) {
  const [isValid, setIsValid] = useState(false);

  return (
    <BasePage title={gettext('Authentication Registration')} pageImage={<LoginImage style={{height: '100%', width: '100%'}} />} {...props}>
      <form style={{display:'flex', gap:'15px', flexDirection:'column', minHeight: 0}} action={actionUrl} method="POST">
        {mfaView ? <>
          {mfaView.auth_method == 'email' &&
            <EmailRegisterView mfaView={mfaView} onValidityChange={setIsValid} />}
          {mfaView.auth_method == 'authenticator' &&
            <AuthenticatorRegisterView mfaView={mfaView} onValidityChange={setIsValid} />}
          <Box display="flex" gap="15px">
            <SecurityButton
              name="continue"
              value="Continue"
              disabled={!isValid}
            >
              {gettext('Continue')}
            </SecurityButton>
            <DefaultButton
              type="submit"
              name="cancel"
              value="Cancel"
              formNoValidate
              style={{width: '100%'}}
            >
              {gettext('Cancel')}
            </DefaultButton>
          </Box>
        </>:<>
          {mfaList?.map((m)=>{
            return (
              <Box display="flex" width="100%" key={m.label}>
                <SecurityAuthIcon style={{
                  width: '10%',
                  mask: `url(${m.icon})`, WebkitMask: `url(${m.icon})`,
                  maskRepeat: 'no-repeat', WebkitMaskRepeat: 'no-repeat',
                }}/>
                <div style={{width: '70%'}}>{m.label}</div>
                <div style={{width: '20%'}}>
                  <SecurityButton name={m.id} value={m.registered ? 'DELETE' : 'SETUP'}>
                    {m.registered ? gettext('Delete') : gettext('Setup')}
                  </SecurityButton>
                </div>
              </Box>
            );
          })}
          {nextUrl != 'internal' &&
            <SecurityButton value="Continue">{gettext('Continue')}</SecurityButton>}
        </>}
        <div><input type="hidden" name="next" value={nextUrl}/></div>
      </form>
    </BasePage>
  );
}

MfaRegisterPage.propTypes = {
  actionUrl: PropTypes.string,
  mfaList: PropTypes.arrayOf(PropTypes.object),
  nextUrl: PropTypes.string,
  mfaView: PropTypes.object
};

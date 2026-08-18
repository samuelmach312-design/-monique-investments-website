##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""
    Utility class providing methods for validating, normalizing and sending
    emails.
"""

from flask import current_app, render_template
from flask_mail import Message


def _config_value(_app, _param, _default=None):
    return _app.config.get(_param, _default)


class _MailUtil:
    """
    Utility class providing methods for sending emails.

    This default class uses the flask_mail package or PEM internal
    functionality to send emails, based on the configuration parameter.
    e.g. MAIL_USE_PEM_INTERNAL

    To provide your own implementation, pass in the class as ``mail_util_cls``
    at init time.
    """

    def __init__(self, app, internal=True):
        """Instantiate class.

        :param app: The Flask application being initialized.
        """
        if _config_value(app, 'MAIL_USE_PEM_INTERNAL', True) is True:
            # Will be used with 2FA
            from pgadmin.pem.utils import PEMMailUtil
            self.state = PEMMailUtil(app, internal=False)

            return

        from flask_mail import Mail
        self.state = Mail(app)

    def send_mail(
        self, subject, recipient, sender, body, html, **kwargs
    ):
        """Send an email via this utility.

        :param subject: Email subject
        :param recipient: Email recipient
        :param sender: who to send email as (see :py:data:
            `SECURITY_EMAIL_SENDER`)
        :param body: the rendered body (text)
        :param html: the rendered body (html)
        """

        from flask_mail import Message

        msg = Message(subject, sender=sender, recipients=[recipient])
        msg.body = body
        msg.html = html

        self.state.send(msg)


def send_mail(subject, recipient, body, html, **kwargs):
    """Send an email.

    :param template: the Template name. The message has already been rendered
        however this might be useful to differentiate why the email is being
        sent.
    :param subject: Email subject
    :param recipient: Email recipient
    :param sender: who to send email as (see :py:data:`SECURITY_EMAIL_SENDER`)
    :param body: the rendered body (text)
    :param html: the rendered body (html)
    """

    util = current_app.extensions['pem_mail_util']
    util.send_mail(
        subject, recipient,
        _config_value(current_app, 'SECURITY_EMAIL_SENDER'),
        body, html, **kwargs
    )


def send_mail_using_template(subject, recipient, template, context, **kwargs):

    body = None
    html = None

    if _config_value(current_app, "EMAIL_PLAINTEXT", True):
        body = render_template("%s.txt" % template, **context)

    if _config_value(current_app, "EMAIL_HTML", False):
        html = render_template("%s.html" % template, **context)

    send_mail(subject, recipient, body, html, **kwargs)


def init_app(app):

    mail_util_cls = _config_value(app, 'mail_util_cls')

    if mail_util_cls is None:
        mail_util_cls = _MailUtil

    state = mail_util_cls(app)

    # register extension with app
    app.extensions = getattr(app, 'extensions', {})
    app.extensions['pem_mail_util'] = state

    return state

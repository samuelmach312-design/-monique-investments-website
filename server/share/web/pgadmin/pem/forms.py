##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2015 - 2025, EnterpriseDB Corporation. All rights reserved.
#
# padmin/pem/forms.py - Login Form
#
##########################################################################
"""Product Registration Form class."""

from flask_wtf import Form
from wtforms import StringField


class ProductRegistrationForm(Form):

    """Product registration Form Fields"""
    product_key = StringField('Product Key', id='product_key')

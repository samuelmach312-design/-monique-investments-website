##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Register preferences for sql profiler"""

from flask_babel import gettext
from pgadmin.utils import SHORTCUT_FIELDS as shortcut_fields


def RegisterSQLProfilerPreferences(self):
    self.preference.register(
        'keyboard_shortcuts', 'btn_open_menu',
        gettext('Open menu'), 'keyboardshortcut',
        {
            'alt': True,
            'shift': True,
            'control': False,
            'key': {
                'key_code': 79,
                'char': 'o'
            }
        },
        category_label=gettext('Keyboard shortcuts'),
        fields=shortcut_fields
    )
    self.preference.register(
        'keyboard_shortcuts',
        'btn_start_trace',
        gettext('Start Trace'),
        'keyboardshortcut',
        {
            'alt': True,
            'shift': True,
            'control': False,
            'key': {
                'key_code': 83,
                'char': 's'
            }
        },
        category_label=gettext('Keyboard shortcuts'),
        fields=shortcut_fields
    )
    self.preference.register(
        'keyboard_shortcuts', 'btn_stop_trace',
        gettext('Accesskey (Stop Trace)'), 'keyboardshortcut',
        {
            'alt': True,
            'shift': True,
            'control': False,
            'key': {
                'key_code': 81,
                'char': 'q'
            }
        },
        category_label=gettext('Keyboard shortcuts'),
        fields=shortcut_fields
    )
    self.preference.register(
        'keyboard_shortcuts', 'btn_refresh_trace',
        gettext('Accesskey (Refresh Trace)'), 'keyboardshortcut',
        {
            'alt': True,
            'shift': True,
            'control': False,
            'key': {
                'key_code': 82,
                'char': 'r'
            }
        },
        category_label=gettext('Keyboard shortcuts'),
        fields=shortcut_fields
    )
    self.preference.register(
        'keyboard_shortcuts', 'btn_clear_trace',
        gettext('Accesskey (Clear Trace)'), 'keyboardshortcut',
        {
            'alt': True,
            'shift': True,
            'control': False,
            'key': {
                'key_code': 67,
                'char': 'c'
            }
        },
        category_label=gettext('Keyboard shortcuts'),
        fields=shortcut_fields
    )
    self.preference.register(
        'keyboard_shortcuts', 'btn_filter_dialog',
        gettext('Accesskey (Filter dialog)'), 'keyboardshortcut',
        {
            'alt': True,
            'shift': True,
            'control': False,
            'key': {
                'key_code': 84,
                'char': 't'
            }
        },
        category_label=gettext('Keyboard shortcuts'),
        fields=shortcut_fields
    )
    self.preference.register(
        'keyboard_shortcuts', 'btn_inform',
        gettext('Accesskey (Properties)'), 'keyboardshortcut',
        {
            'alt': True,
            'shift': True,
            'control': False,
            'key': {
                'key_code': 80,
                'char': 'p'
            }
        },
        category_label=gettext('Keyboard shortcuts'),
        fields=shortcut_fields
    )
    self.preference.register(
        'keyboard_shortcuts',
        'download_csv',
        gettext('Download CSV'),
        'keyboardshortcut',
        {
            'alt': True,
            'shift': True,
            'control': False,
            'key': {
                'key_code': 86,
                'char': 'v'
            }
        },
        category_label=gettext('Keyboard shortcuts'),
        fields=shortcut_fields
    )
    self.preference.register(
        'keyboard_shortcuts',
        'move_previous',
        gettext('Previous tab'),
        'keyboardshortcut',
        {
            'alt': True,
            'shift': True,
            'control': False,
            'key': {
                'key_code': 219,
                'char': '['
            }
        },
        category_label=gettext('Keyboard shortcuts'),
        fields=shortcut_fields
    )

    self.preference.register(
        'keyboard_shortcuts',
        'move_next',
        gettext('Next tab'),
        'keyboardshortcut',
        {
            'alt': True,
            'shift': True,
            'control': False,
            'key': {
                'key_code': 221,
                'char': ']'
            }
        },
        category_label=gettext('Keyboard shortcuts'),
        fields=shortcut_fields
    )
    self.preference.register(
        'keyboard_shortcuts',
        'switch_panel',
        gettext('Switch Panel'),
        'keyboardshortcut',
        {
            'alt': True,
            'shift': True,
            'control': False,
            'key': {
                'key_code': 9,
                'char': 'Tab'
            }
        },
        category_label=gettext('Keyboard shortcuts'),
        fields=shortcut_fields
    )

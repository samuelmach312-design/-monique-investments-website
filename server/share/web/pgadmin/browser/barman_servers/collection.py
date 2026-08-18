##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Implement CollectionNodeModule for the Barman Server children nodes"""

from flask_babel import gettext
from pgadmin.browser.collection import CollectionNodeModule \
    as _CollectionNodeModule
from pgadmin.utils.preferences import Preferences


class CollectionNodeModule(_CollectionNodeModule):
    """
    class CollectionNodeModule(_CollectionNodeModule):

        This class represents the collection node modules for Barman Server
        children node module, and define the pref_show_node under the Barman
        Server preferences.
    """
    def register_preferences(self):
        """
        register_preferences
        Register preferences for this module.

        Keep the browser preference object to be used by overriden submodule,
        along with that get two browser level preferences show_system_objects,
        and show_node will be registered to used by the submodules.
        """
        # Add the node informaton for browser, not in respective node
        # preferences
        self.browser_preference = Preferences.module('browser')
        self.pref_show_system_objects = self.browser_preference.preference(
            'show_system_objects'
        )
        self.barman_server_preference = \
            Preferences.module('NODE-barman_server')
        self.pref_show_node = self.barman_server_preference.register(
            'node', 'show_node_' + self.node_type,
            self.collection_label, 'node', self.SHOW_ON_BROWSER,
            category_label=gettext('Nodes')
        )

##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Register Alert API view with blueprint"""
from pgadmin.pem.monitor.alerts.api.config import GlobalConfigApiView, \
    AgentConfigApiView, ServerConfigApiView, DatabaseConfigApiView, \
    SchemaConfigApiView, TableConfigApiView, IndexConfigApiView, \
    SequenceConfigApiView, FunctionConfigApiView, GlobalConfigApiV5View, \
    AgentConfigApiV5View, ServerConfigApiV5View, DatabaseConfigApiV5View, \
    SchemaConfigApiV5View, TableConfigApiV5View, IndexConfigApiV5View, \
    SequenceConfigApiV5View, FunctionConfigApiV5View
from pgadmin.pem.monitor.alerts.api.custom import AlertTemplateApiV1View, \
    AlertTemplateApiV2View
from pgadmin.pem.monitor.alerts.api.email import EmailGroupsApiView

# Import API Views for copy probe support
from pgadmin.pem.monitor.alerts.api.copy import AgentCopyApiView, \
    ServerCopyApiView, DatabaseCopyApiView, SchemaCopyApiView, \
    TableCopyApiView, IndexCopyApiView, SequenceCopyApiView, \
    FunctionCopyApiView

from pgadmin.pem.monitor.alerts.api.status import AlertStatusApiView
from pgadmin.pem.monitor.alerts.api.history import AlertHistoryApiView, \
    AgentAlertHistoryApiView, ServerAlertHistoryApiView, \
    DatabaseAlertHistoryApiView

from pgadmin.pem.monitor.alerts.api.webhook import WebhookApiView

from pgadmin.pem.monitor.alerts.api.alert_template_import_export import \
    AlertTemplateExportApiView, AlertTemplateImportApiView

from pgadmin.pem.api.utils import create_api_view

# V1 and V2 apis

# Register API View for Alert Configuration.
create_api_view(GlobalConfigApiView)
create_api_view(AgentConfigApiView)
create_api_view(ServerConfigApiView)
create_api_view(DatabaseConfigApiView)
create_api_view(SchemaConfigApiView)
create_api_view(TableConfigApiView)
create_api_view(IndexConfigApiView)
create_api_view(SequenceConfigApiView)
create_api_view(FunctionConfigApiView)


# Register API View for Email groups.
create_api_view(EmailGroupsApiView)

# Register API View for Copy Probe Configuration.
create_api_view(AgentCopyApiView)
create_api_view(ServerCopyApiView)
create_api_view(DatabaseCopyApiView)
create_api_view(SchemaCopyApiView)
create_api_view(TableCopyApiView)
create_api_view(IndexCopyApiView)
create_api_view(SequenceCopyApiView)
create_api_view(FunctionCopyApiView)


# Only V1 apis
# Register API View for Alert Templates.
create_api_view(AlertTemplateApiV1View)


# Only V2 apis
create_api_view(AlertTemplateApiV2View)

# V4 plus apis
create_api_view(AlertStatusApiView)
create_api_view(AlertHistoryApiView)
create_api_view(AgentAlertHistoryApiView)
create_api_view(ServerAlertHistoryApiView)
create_api_view(DatabaseAlertHistoryApiView)

# V5 plus apis
create_api_view(WebhookApiView)

# Register API View for Alert Configuration
create_api_view(GlobalConfigApiV5View)
create_api_view(AgentConfigApiV5View)
create_api_view(ServerConfigApiV5View)
create_api_view(DatabaseConfigApiV5View)
create_api_view(SchemaConfigApiV5View)
create_api_view(TableConfigApiV5View)
create_api_view(IndexConfigApiV5View)
create_api_view(SequenceConfigApiV5View)
create_api_view(FunctionConfigApiV5View)

# V6 Register API view for Import/Export Alert templates
create_api_view(AlertTemplateExportApiView)
create_api_view(AlertTemplateImportApiView)

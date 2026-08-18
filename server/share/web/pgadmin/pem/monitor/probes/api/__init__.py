##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Register Probe API with blueprint"""
from pgadmin.pem.api.utils import create_api_view

# Import API Views for probe configurations
from pgadmin.pem.monitor.probes.api.config import AgentConfigApiView, \
    ServerConfigApiView, DatabaseConfigApiView, SchemaConfigApiView, \
    TableConfigApiView, IndexConfigApiView, SequenceConfigApiView, \
    FunctionConfigApiView, ViewConfigApiView

# Import API Views for probe data
from pgadmin.pem.monitor.probes.api.data import AgentProbeDataView, \
    ServerProbeDataView, DatabaseProbeDataView, SchemaProbeDataView, \
    TableProbeDataView, IndexProbeDataView, SequenceProbeDataView,  \
    FunctionProbeDataView, ViewProbeDataView, AgentProbeHistoryView,  \
    ServerProbeHistoryView, DatabaseProbeHistoryView, SchemaProbeHistoryView, \
    TableProbeHistoryView, IndexProbeHistoryView, SequenceProbeHistoryView, \
    FunctionProbeHistoryView, ViewProbeHistoryView

# Import API Views for copy probe support
from pgadmin.pem.monitor.probes.api.copy import AgentCopyApiView, \
    ServerCopyApiView, DatabaseCopyApiView, SchemaCopyApiView

# Import API Views for probe for CRUD operation
from pgadmin.pem.monitor.probes.api.probes import ProbesApiView

from pgadmin.pem.monitor.probes.api.probe_import_export import \
    ProbeExportApiView, ProbeImportApiView


# Register API View for Probe Configuration.
create_api_view(AgentConfigApiView)
create_api_view(ServerConfigApiView)
create_api_view(DatabaseConfigApiView)
create_api_view(SchemaConfigApiView)
create_api_view(TableConfigApiView)
create_api_view(IndexConfigApiView)
create_api_view(SequenceConfigApiView)
create_api_view(FunctionConfigApiView)
create_api_view(ViewConfigApiView)


# Register API View for Probe Data.
create_api_view(AgentProbeDataView)
create_api_view(ServerProbeDataView)
create_api_view(DatabaseProbeDataView)
create_api_view(SchemaProbeDataView)
create_api_view(TableProbeDataView)
create_api_view(IndexProbeDataView)
create_api_view(SequenceProbeDataView)
create_api_view(FunctionProbeDataView)
create_api_view(ViewProbeDataView)
create_api_view(AgentProbeHistoryView)
create_api_view(ServerProbeHistoryView)
create_api_view(DatabaseProbeHistoryView)
create_api_view(SchemaProbeHistoryView)
create_api_view(TableProbeHistoryView)
create_api_view(IndexProbeHistoryView)
create_api_view(SequenceProbeHistoryView)
create_api_view(FunctionProbeHistoryView)
create_api_view(ViewProbeHistoryView)

# Register API View for Copy Probe Configuration.
create_api_view(AgentCopyApiView)
create_api_view(ServerCopyApiView)
create_api_view(DatabaseCopyApiView)
create_api_view(SchemaCopyApiView)

# Register API View for probes.
create_api_view(ProbesApiView)

# V6 plus apis
create_api_view(ProbeExportApiView)
create_api_view(ProbeImportApiView)

##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

def pem_modules():
    from .api import blueprint as ApiModule
    from .management.misc import blueprint as MiscUtilitiesModule
    from . management.metrics import blueprint as MetricsModule
    from .management.tasks import blueprint as TasksModule
    from .management.tuning_wizard import blueprint as TuningWizardModule
    from .management.log_analysis_expert import blueprint as \
        LogAnalysisExpertModule
    from .management.log_analysis_expert import blueprint as \
        LogAnalysisExpertModule
    from .management.log_manager import blueprint as \
        LogManagerModule
    from .management.capacity_manager import blueprint as \
        CapacityManagerModule
    from .management.audit_manager import blueprint as \
        AuditManagerModule
    from .management.postgres_expert import blueprint as \
        PostgresExpertModule
    from .monitor.probes import blueprint as \
        ProbesModule
    from .monitor.auto_discovery import blueprint as \
        AutoDiscoveryModule
    from .monitor.charts import blueprint as \
        ChartsModule
    from .monitor.charts.manage import blueprint as \
        ManageChartsModule
    from .monitor import blueprint as \
        MonitorModule
    from .monitor.custom_dashboard import blueprint as \
        ManageDashboardModule
    from .monitor.alerts import blueprint as \
        AlertsModule
    from .management.manage_profile import blueprint as \
        ManageProfileModule
    from .monitor.dashboard import blueprint as \
        PEMDashboardModule
    from .server_config import blueprint as \
        ServerConfigModule
    from .tools.performance_diagnostic import blueprint as \
        PerformanceDiagnosticModule
    from .tools.alert_history_report import blueprint as \
        AlertHistoryReportModule
    from .tools.core_usage_report import blueprint as \
        CoreUsageReportModule
    from .tools.profiler import blueprint as \
        ProfilerModule
    from .tools.system_config_report import blueprint as \
        SystemConfigReportModule

    return [
        ApiModule,
        MiscUtilitiesModule,
        MetricsModule,
        TasksModule,
        TuningWizardModule,
        LogAnalysisExpertModule,
        LogManagerModule,
        CapacityManagerModule,
        AuditManagerModule,
        PostgresExpertModule,
        ProbesModule,
        AutoDiscoveryModule,
        ChartsModule,
        ManageChartsModule,
        MonitorModule,
        ManageDashboardModule,
        AlertsModule,
        ManageProfileModule,
        PEMDashboardModule,
        ServerConfigModule,
        PerformanceDiagnosticModule,
        AlertHistoryReportModule,
        CoreUsageReportModule,
        ProfilerModule,
        SystemConfigReportModule
    ]

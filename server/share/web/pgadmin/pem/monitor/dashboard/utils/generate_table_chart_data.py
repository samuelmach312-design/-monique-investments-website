##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
from datetime import datetime
import pytz

# Type code to type mapping
TYPE_CODE_MAPPING = {
    23: "integer",
    16: "boolean",
    25: "text",
    1700: "numeric",
    20: "bigint",
    1043: "varchar",
    1184: "timestamptz",
    1114: "timestamp",
    1009: "text[]"
}

# Custom column name to type mapping
TYPE_MAP = {
    2: {
        "Blackout": "blackout_type",
        "Status": "status_type",
        "Name": "agent_name_type",
    },
    3: {
        "Blackout": "blackout_type",
        "Status": "status_type",
        "Name": "server_name_type",
    },
    4: {
        "Alarm Type": "alert_type",
        "Alert Name": "alert_name_type",
        "Status": "status_type",
    },
    6: {
        "Ack'ed": "acknowledgment_type",
        "Name": "alert_name_type",
        "Alert Type": "alert_type",
    },
    7: {
        "Alert Type": "alert_error_type",
        "Name": "alert_name_type",
    },
    104: {
        "Peer State": "peer_state_type",
        "Peer Target State": "peer_target_state_type",
    }
}

# Paths based on levels
LEVEL_PATHS = {
    'server_status': 'server/server',
    'agent_status': 'os/agent',
    'alert_status': 'alerts/view'
}


def generate_json_for_table_chart(res, level=None, table_id=None):
    """Generate necessary JSON for table charts."""
    is_nested = level in ['alert_status', 'bdr_workers', 'alert_details']
    return ({
        'is_nested': is_nested,
        'columns': transform_columns(res['columns'], level, table_id),
        'data': transform_data(res['rows'], res['columns'], level)
    })


def transform_columns(columns, level, table_id):
    """Transform columns with appropriate types."""
    return [
        {
            'label': col.get('display_name', col['name']),
            'id': col['name'],
            'type': get_column_type(col, level, table_id)
        }
        for col in columns
    ]


def get_column_type(col, level, table_id):
    """Return the column type based on type mappings, level, and table_id."""
    col_name = col['name']

    if table_id in TYPE_MAP and col_name in TYPE_MAP[table_id]:
        col_type = TYPE_MAP[table_id][col_name]
    else:
        col_type = TYPE_MAP.get(col_name, TYPE_CODE_MAPPING.get(
            col['type_code'], "unknown"))

    return col_type


def transform_data(rows, columns, level=None):
    """Transform data rows."""
    transformed_rows = []

    for row in rows:
        transformed_row = {}

        for col in columns:
            key = col['name']
            value = row.get(key)
            # Check if the column is of timestamp type based on
            # TYPE_CODE_MAPPING
            if col['type_code'] in [1043, 1184, 1114]:
                if is_valid_date_string(value):
                    transformed_row[key] = convert_to_epoch(value)
                else:
                    transformed_row[key] = value
            else:
                transformed_row[key] = value

        transformed_rows.append(transformed_row)

    return transformed_rows


def is_valid_date_string(value):
    """Check if the value is a valid date string."""
    return (isinstance(value, str) and
            not value.replace('.', '', 1).isdigit())


def convert_to_epoch(value):
    """Convert a valid date string to epoch."""
    try:
        # Try parsing with timezone
        dt = datetime.strptime(value, '%Y-%m-%d %H:%M:%S.%f%z')
    except ValueError:
        try:
            # Try parsing without timezone (assuming UTC)
            dt = datetime.strptime(value, '%Y-%m-%d %H:%M:%S.%f')
            dt = pytz.UTC.localize(dt)
        except ValueError:
            try:
                # If microseconds are not present, parse without them
                dt = datetime.strptime(value, '%Y-%m-%d %H:%M:%S')
                dt = pytz.UTC.localize(dt)
            except ValueError:
                return value
    return dt.timestamp()

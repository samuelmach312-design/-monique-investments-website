##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""
Utility functions for the Manage Profiles feature.

This module handles the business logic for creating, reading, updating,
and deleting profiles, including the 'Draft & Published' workflow.
"""

from flask import current_app, render_template
from flask_security import current_user
import json
from flask_babel import gettext
from .alerts import prepare_add_alert_data


class ProfileOperationError(RuntimeError):
    """Domain specific error for profile operations."""
    def __init__(self, message):  # explicit to avoid 'pass' / ellipsis
        super().__init__(message)


def get_profiles(pem_conn, target_kind=None):
    """Fetches all PUBLISHED profiles."""
    if target_kind:
        sql = render_template(
            'profiles.sql',
            get_published_list_by_target=True)
        status, res = pem_conn.execute_dict(sql, {'target_kind': target_kind})
    else:
        sql = render_template('profiles.sql', get_published_if_not_draft=True)
        status, res = pem_conn.execute_dict(sql)
    return (True, res['rows']) if status else (False, res)


def get_profile_for_server(pem_conn, server_id):
    """Fetches profile details for server."""
    profile_details = {
        'has_profile': False
    }
    if server_id:
        sql = render_template(
            'profiles.sql',
            get_profile_details_for_server=True)
        status, res = pem_conn.execute_dict(sql, {'server_id': server_id})
        if not status:
            return False, res
        data = res.get('rows',[])
        if len(data) > 0:
            profile_details.update(data[0])
            profile_details['has_profile'] = True
    else:
        return False, gettext("Invalid server id.")
    return (True,profile_details) if status else (False, res)


def get_profile_for_agent(pem_conn, agent_id):
    """Fetches profile details for agent."""
    profile_details = {
        'has_profile': False
    }
    if agent_id:
        sql = render_template(
            'profiles.sql',
            get_profile_for_agent=True)
        status, res = pem_conn.execute_dict(sql, {'agent_id': agent_id})
        if not status:
            return False, res
        data = res.get('rows',[])
        if len(data) > 0:
            profile_details.update(data[0])
            profile_details['has_profile'] = True
    else:
        return False, gettext("Invalid agent id.")
    return (True, profile_details) if status else (False, res)


def save_profiles(change_data, pem_conn):
    """
    Orchestrates the bulk saving of profile changes (creations, updates,
    and deletions) within a single, safe database transaction.
    """
    try:
        # Start a single transaction for the entire save operation.
        # This ensures that all changes succeed or none of them do.
        pem_conn.execute_void('BEGIN')

        # For efficiency, pre-render all SQL templates at the beginning.
        sql_templates = {
            'delete': render_template(
                'profiles.sql', delete_profile=True),
            'get_status': render_template(
                'profiles.sql', get_profile_status=True),
            'get_draft': render_template(
                'profiles.sql', get_draft=True),
            'create_draft': render_template(
                'profiles.sql', create_draft_from_parent=True),
            'copy_probes': render_template(
                'profiles.sql', copy_probe_config_to_draft=True),
            'copy_alerts': render_template(
                'profiles.sql', copy_alert_config_to_draft=True),
            'probe_upsert': render_template(
                'profile_probe_config.sql', upsert_probe_config=True),
            'alert_insert': render_template(
                'profile_alert_config.sql', upsert_alerts=True),
            'alert_update': render_template(
                'profile_alert_config.sql', update_alert_config=True),
            'delete_alert_config': render_template(
                'profile_alert_config.sql', delete_alert_config=True),
            'check_profile_assignment': render_template(
                'profiles.sql', check_profile_assignment=True)
        }

        if 'deleted' in change_data and change_data['deleted']:
            deleted_ids = _handle_deleted_profiles(
                pem_conn, change_data['deleted'], sql_templates)
            for pid in deleted_ids:
                _log_profile_event(
                    pem_conn,
                    operation='delete',
                    message=f"Deleted profile {pid}",
                    details={
                        'ProfileId': pid,
                        'ChangedCategories': ['delete']
                    }
                )

        if 'added' in change_data and change_data['added']:
            new_profile_ids = _handle_added_profiles(
                pem_conn, change_data['added'], sql_templates)
            for added in new_profile_ids:
                _log_profile_event(
                    pem_conn,
                    operation='create',
                    message=f"Created profile {added['id']}",
                    details={
                        'ProfileId': added['id'],
                        'Name': added['name'],
                        'TargetKind': added['target_kind'],
                        'AlertTemplates': added['alert_template_ids'],
                        'ChangedCategories': ['metadata', 'probe', 'alert']
                    }
                )

        if 'changed' in change_data and change_data['changed']:
            changed_profiles = _handle_changed_profiles(
                pem_conn, change_data['changed'], sql_templates)
            for ch in changed_profiles:
                # Skip logging if nothing actually changed (empty categories)
                if not ch.get('changed_categories'):
                    continue
                _log_profile_event(
                    pem_conn,
                    operation='update',
                    message=f"Updated profile {ch['profile_id']}",
                    details={
                        'ProfileId': ch['profile_id'],
                        'DraftId': ch.get('draft_id'),
                        'WasAssigned': ch.get('was_assigned'),
                        'ProbeConfigs': ch['probes_changed'],
                        'AlertsChanged': ch['alerts_changed'],
                        'ChangedCategories': ch['changed_categories']
                    }
                )

        # If all operations were successful, commit the transaction.
        pem_conn.execute_void('COMMIT')
        return True, gettext("Profiles saved successfully.")

    except (ProfileOperationError, RuntimeError, ValueError, LookupError) as e:
        pem_conn.execute_void('ROLLBACK')
        return False, str(e)


def publish_draft(pem_conn, target_id):
    """
    Publishes a draft, making probe/alert configurations live,
    AND then reapplies the alert configurations to all assigned servers/agents.
    Executes all steps within a single transaction.
    """
    # 1. Determine if draft_id is a parent (published) or a draft.
    status, res = pem_conn.execute_dict(
        "SELECT id, parent_id, status FROM pem.profile WHERE id = %(id)s",
        {'id': target_id}
    )
    if not status or not res['rows']:
        return False, gettext("Profile not found.")
    draft_id = None
    profile_info = res['rows'][0]
    if profile_info['status'] == 'published':
        # If draft_id is actually the parent, find the draft for this parent.
        status, draft_res = pem_conn.execute_dict(
            "SELECT id FROM pem.profile WHERE parent_id = %(parent_id)s "
            "AND status = 'draft'",
            {'parent_id': profile_info['id']}
        )
        if not status or not draft_res['rows']:
            return False, gettext(
                "Draft not found for this published profile."
            )
        draft_id = draft_res['rows'][0]['id']
        parent_id = profile_info['id']
    elif profile_info['status'] == 'draft':
        # If draft_id is a draft, get its parent.
        parent_id = profile_info['parent_id']
    else:
        return False, gettext("Invalid profile status.")

    # Set params depending on whether target_id is a draft or published profile
    if profile_info['status'] == 'published':
        # We found the published profile, and looked up its draft above
        params = {'draft_id': draft_id, 'parent_id': parent_id}
    elif profile_info['status'] == 'draft':
        # target_id is a draft, parent_id is the published profile
        params = {'draft_id': target_id, 'parent_id': parent_id}
    else:
        return False, gettext("Invalid profile status.")

    try:
        # Start the main transaction for the entire publish process.
        pem_conn.execute_void('BEGIN')

        # --- Render SQL templates needed ---
        sql_publish_delete_old_probe = render_template(
            'profiles.sql', publish_delete_old_probe_config=True)
        sql_publish_promote_probes = render_template(
            'profiles.sql', publish_promote_probes=True)
        sql_publish_delete_old_alert = render_template(
            'profiles.sql', publish_delete_old_alert_config=True)
        sql_publish_promote_alerts = render_template(
            'profiles.sql', publish_promote_alerts=True)
        sql_publish_update_meta = render_template(
            'profiles.sql', publish_update_meta=True)
        sql_publish_delete_draft = render_template(
            'profiles.sql', publish_delete_draft=True)

        # --- Step 2: Promote Draft Configs to Published Profile ---

        # Promote Probes
        status, res = pem_conn.execute_void(
            sql_publish_delete_old_probe, params)
        if not status:
            raise ProfileOperationError(
                f"Failed deleting old probe configs: {res}")
        status, res = pem_conn.execute_void(
            sql_publish_promote_probes, params)
        if not status:
            raise ProfileOperationError(
                f"Failed promoting probe configs: {res}")

        # Promote Alerts
        status, res = pem_conn.execute_void(
            sql_publish_delete_old_alert, params)
        if not status:
            raise ProfileOperationError(
                f"Failed deleting old alert configs: {res}")
        status, res = pem_conn.execute_void(
            sql_publish_promote_alerts, params)
        if not status:
            raise ProfileOperationError(
                f"Failed promoting alert configs: {res}")

        # Update Metadata
        status, res = pem_conn.execute_void(
            sql_publish_update_meta, params)
        if not status:
            raise ProfileOperationError(
                f"Failed updating profile metadata: {res}")

        # Delete Draft Profile Row
        status, res = pem_conn.execute_void(
            sql_publish_delete_draft, params)
        if not status:
            raise ProfileOperationError(
                f"Failed deleting draft profile row: {res}")

        # --- Step 3: Re-apply Alert Configs to Assigned Targets ---

        # Find servers assigned to this profile (using the parent_id)
        status, servers = pem_conn.execute_dict(
            "SELECT id FROM pem.server WHERE profile_id = %(pid)s",
            {'pid': parent_id}
        )
        if not status:
            raise ProfileOperationError(
                f"Failed querying assigned servers: {servers}")

        # Find agents assigned to this profile
        status, agents = pem_conn.execute_dict(
            "SELECT id FROM pem.agent WHERE profile_id = %(pid)s",
            {'pid': parent_id}
        )
        if not status:
            raise ProfileOperationError(
                f"Failed querying assigned agents: {agents}")

        # Apply alerts to each assigned server
        for server in servers['rows']:
            server_id = server['id']
            current_app.logger.info(
                f"Re-applying alert profile {parent_id} to server {server_id}")
            # Call the PostgreSQL function directly
            status_apply, res_apply = pem_conn.execute_scalar(
                "SELECT pem.apply_alert_profile_to_target(%(pid)s, 'server', "
                "%(tid)s)",
                {'pid': parent_id, 'tid': server_id}
            )
            # execute_scalar returns None on success for VOID functions,
            # error string on failure
            if not status_apply and res_apply is not None:
                raise ProfileOperationError(
                    f"Failed applying alerts to server {server_id}: "
                    f"{res_apply}"
                )

        # Apply alerts to each assigned agent
        for agent in agents['rows']:
            agent_id = agent['id']
            current_app.logger.info(
                f"Re-applying alert profile {parent_id} to agent {agent_id}")
            # Call the PostgreSQL function directly
            status_apply, res_apply = pem_conn.execute_scalar(
                "SELECT pem.apply_alert_profile_to_target(%(pid)s, 'agent', "
                "%(tid)s)",
                {'pid': parent_id, 'tid': agent_id}
            )
            if not status_apply and res_apply is not None:
                raise ProfileOperationError(
                    f"Failed applying alerts to agent {agent_id}: {res_apply}")

        # --- Step 4: Commit the entire transaction ---
        pem_conn.execute_void('COMMIT')

        # Immediate refresh: profile publish can materially change which
        # probes are enabled/disabled for multiple targets; refresh now to
        # avoid UI latency.
        try:
            status, err = pem_conn.execute_void(
                "SELECT pem.refresh_stale_probe_view();"
            )
            if not status:
                current_app.logger.warning(
                    "Immediate probe view refresh after "
                    "profile publish failed: %s", err
                )
        except Exception as e_inner:
            current_app.logger.warning(
                "Exception during immediate probe view refresh "
                "after profile publish: %s", e_inner
            )

        # Collect applied targets for audit details.
        applied_servers = [s['id'] for s in servers['rows']]
        applied_agents = [a['id'] for a in agents['rows']]

        applied_targets_detail = {}
        if applied_servers:
            applied_targets_detail['Servers'] = applied_servers
        if applied_agents:
            applied_targets_detail['Agents'] = applied_agents

        details_payload = {
            'ProfileId': parent_id,
            'DraftId': params['draft_id'],
            'ChangedCategories': ['publish']
        }
        if applied_targets_detail:
            details_payload['AppliedToTargets'] = applied_targets_detail

        _log_profile_event(
            pem_conn,
            operation='publish',
            message=f"Published profile {parent_id}",
            details=details_payload
        )

        return True, gettext("Profile published and applied successfully.")

    except ProfileOperationError as e:
        pem_conn.execute_void('ROLLBACK')
        current_app.logger.error(
            f"Error during profile publish for draft {draft_id}: {e}")
        return False, str(e)


def delete_draft(pem_conn, draft_id):
    """
    Deletes a single draft profile.
    The CASCADE constraint on the database will automatically clean up
    the associated probe/alert configurations for this draft.
    """
    sql = render_template('profiles.sql', delete_draft=True)
    params = {'draft_id': draft_id}
    status, res = pem_conn.execute_void(sql, params)
    if status:
        _log_profile_event(
            pem_conn,
            operation='rollback',
            message=f"Rolled back draft {draft_id}",
            details={
                'DraftId': draft_id,
                'ChangedCategories': ['rollback']
            }
        )
        return True, gettext("Draft reverted successfully.")
    else:
        return False, res


# ----------------------------------------------------------------------- #
#                       INTERNAL HELPER FUNCTIONS                         #
# ----------------------------------------------------------------------- #

def _handle_deleted_profiles(pem_conn, deleted_data, sql_templates):
    """
    Handles the deletion of profiles.
    Returns list of deleted published profile IDs.
    """
    deleted_ids = [p['id'] for p in deleted_data if 'id' in p]
    if not deleted_ids:
        return []

    # This logic ensures that if a user deletes a draft from the UI,
    # the entire published profile is deleted.
    status, res = pem_conn.execute_dict(
        (
            "SELECT id, parent_id, status "
            "FROM pem.profile WHERE id = ANY(%(ids)s)"
        ),
        {'ids': deleted_ids}
    )
    if not status:
        raise ProfileOperationError(res)

    final_ids_to_delete = set()
    for profile in res['rows']:
        if profile['status'] == 'draft':
            # If it's a draft, target its parent for deletion.
            final_ids_to_delete.add(profile['parent_id'])
        else:
            # If it's already a published profile, target it directly.
            final_ids_to_delete.add(profile['id'])

    if final_ids_to_delete:
        status, res = pem_conn.execute_void(
            sql_templates['delete'], {'ids': list(final_ids_to_delete)}
        )
        if not status:
            raise ProfileOperationError(res)
    return list(final_ids_to_delete)


def _handle_added_profiles(pem_conn, added_data, sql_templates):
    """
    Handles the creation of new published profiles.
    Returns list of dicts with created profile metadata for auditing.
    """
    created = []
    for profile in added_data:
        # 1. Create the main profile row and get its new ID.
        raw_desc = profile.get('description')
        sql_create = render_template(
            'profiles.sql', create_profile=True, description=raw_desc
        )
        params = {
            'name': profile.get('name'),
            'description': raw_desc,
            'target_kind': profile.get('target_kind')
        }
        status, new_id = pem_conn.execute_scalar(sql_create, params)
        if not status:
            raise ProfileOperationError(new_id)

        # 2. Loop through and insert the associated probe configurations.
        probe_ids = []
        for probe_config in profile.get('target_probe_configs', []):
            probe_config['profile_id'] = new_id
            probe_config_params = {
                'profile_id': new_id,
                'probe_id': probe_config.get('probe_id'),
                'enabled': probe_config.get('enabled', False),
                'enabled_by_default': probe_config.get(
                    'use_default_enabled', True),
                'execution_frequency': probe_config.get('interval', 60),
                'lifetime': probe_config.get('lifetime', 30),
            }
            status, res = pem_conn.execute_void(
                sql_templates['probe_upsert'], probe_config_params)
            if not status:
                raise ProfileOperationError(res)
            probe_ids.append(probe_config_params['probe_id'])

        alert_template_ids = []
        for alert_config in profile.get('target_alert_configs', []):
            status, alert_data = prepare_add_alert_data(
                alert_data=alert_config, pem_conn=pem_conn)
            if status:
                alert_data['profile_id'] = new_id
                alert_data['alert_id'] = 0
            status, res = pem_conn.execute_void(
                sql_templates['alert_insert'], alert_data)
            if not status:
                raise ProfileOperationError(res)
            if 'template_id' in alert_data:
                alert_template_ids.append(alert_data['template_id'])
        created.append({
            'id': new_id,
            'name': params.get('name'),
            'target_kind': params.get('target_kind'),
            'probe_ids': probe_ids,
            'alert_template_ids': alert_template_ids
        })
    return created


def _handle_changed_profiles(pem_conn, changed_data, sql_templates):
    """
    Handles updates to existing profiles by managing the draft workflow.
    Returns list of change summaries for auditing.
    """
    audit_changes = []
    for profile in changed_data:
        ambiguous_id = profile.get('id')
        if not ambiguous_id:
            raise ValueError(gettext("'id' is required for an update."))

        # Step 1: Resolve the ambiguous ID from the UI.
        # This query determines if the ID is for a draft or a published profile
        # and finds the true parent ID.
        status, res = pem_conn.execute_dict(
            sql_templates['get_status'],
            {'id': ambiguous_id}
        )
        if not status or not res['rows']:
            raise LookupError(
                gettext("Profile with ID {0} not found.").format(
                    ambiguous_id))

        profile_info = res['rows'][0]
        if profile_info['status'] == 'published':
            parent_id = ambiguous_id
        else:  # It's a draft
            parent_id = profile_info['parent_id']

        if parent_id is None:
            raise LookupError(gettext(
                "Could not determine parent profile for ID {0}."
            ).format(ambiguous_id))

    # Step 2: Check if the profile is assigned to any server or agent.
        status, res = pem_conn.execute_dict(
            sql_templates['check_profile_assignment'],
            {'profile_id': parent_id}
        )
        if not status:
            raise ProfileOperationError(
                gettext("Failed to check profile assignment."))

        assigned = bool(
            res['rows'] and
            int(res['rows'][0].get('assigned_count', 0)) > 0
        )

        if assigned:
            # Find or create draft
            draft_info = _get_or_create_draft(
                pem_conn, parent_id, sql_templates
            )
            target_id = draft_info['id']
        else:
            target_id = parent_id
            draft_info = profile_info  # reuse for metadata comparison

        # Step 4: Update the draft's metadata(name, description)
        # ONLY if it has changed.
        new_name = profile.get('name')
        new_description = profile.get('description')
        # Compare new values from the UI with the current values in the draft.
        metadata_changed = False
        if (
            (new_name is not None and new_name != draft_info['name']) or
            (
                new_description is not None and
                new_description != draft_info['description']
            )
        ):
            meta_params = {'id': target_id}
            # Render SQL with only the changed fields defined for Jinja.
            name_arg = (
                new_name
                if (new_name is not None and new_name != draft_info['name'])
                else None
            )
            desc_arg = (
                new_description if (
                    new_description is not None and
                    new_description != draft_info['description']
                ) else None
            )
            sql_update = render_template(
                'profiles.sql', update_profile=True,
                name=name_arg, description=desc_arg
            )
            if name_arg is not None:
                meta_params['name'] = name_arg
            if desc_arg is not None:
                meta_params['description'] = desc_arg
            status, res = pem_conn.execute_void(sql_update, meta_params)
            if not status:
                raise ProfileOperationError(res)
            metadata_changed = True

        # Step 5: Update the draft's probe configurations.
        probe_configs = profile.get('target_probe_configs', {})
        probes_changed_summary = []
        if 'changed' in probe_configs:
            for probe_change in probe_configs['changed']:
                params = {
                    'profile_id': target_id,
                    'probe_id': probe_change.get('probe_id'),
                    'enabled': probe_change.get('enabled', None),
                    'enabled_by_default': probe_change.get(
                        'enabled_by_default', None
                    ),
                    'execution_frequency': probe_change.get(
                        'execution_frequency', None
                    ),
                    'lifetime': probe_change.get('lifetime', None)
                }
                status, res = pem_conn.execute_void(
                    sql_templates['probe_upsert'], params)
                if not status:
                    raise ProfileOperationError(res)
                summary_entry = {'ProbeId': params['probe_id']}
                for key_map in [
                    ('enabled', 'enabled'),
                    ('enabled_by_default', 'enabled_by_default'),
                    ('execution_frequency', 'execution_frequency'),
                    ('lifetime', 'lifetime')
                ]:
                    src_key, out_key = key_map
                    if src_key in probe_change:  # include only if user sent it
                        summary_entry[out_key] = params[src_key]
                probes_changed_summary.append(summary_entry)

        alert_configs = profile.get('target_alert_configs', {})
        alerts_changed_summary = []

        if 'changed' in alert_configs:
            for alert_config in alert_configs['changed']:
                # Normalize incoming identifier (supports 'alert_id' or 'id').
                incoming_id = (
                    alert_config.get('alert_id') or
                    alert_config.get('id')
                )
                mapped_id = incoming_id
                if assigned and incoming_id is not None:
                    # Operate only on the draft copy; remap published IDs
                    # to draft counterpart via (template_id, name).
                    status_row, res_row = pem_conn.execute_dict(
                        'SELECT id, profile_id, template_id, name FROM '
                        'pem.profile_alert_configs WHERE id = %(id)s',
                        {'id': incoming_id}
                    )
                    if status_row and res_row['rows']:
                        row = res_row['rows'][0]
                        if (
                            row['profile_id'] == parent_id and
                            row['profile_id'] != target_id
                        ):
                            # Published row; find draft sibling.
                            status_map, res_map = pem_conn.execute_dict(
                                'SELECT id FROM pem.profile_alert_configs '
                                'WHERE profile_id = %(draft_id)s '
                                'AND template_id = %(template_id)s '
                                'AND name = %(name)s',
                                {
                                    'draft_id': target_id,
                                    'template_id': row['template_id'],
                                    'name': row['name']
                                }
                            )
                            if status_map and res_map['rows']:
                                mapped_id = res_map['rows'][0]['id']
                            else:
                                # Draft copy missing; skip.
                                continue
                        elif row['profile_id'] == target_id:
                            # Already a draft id; keep as-is.
                            mapped_id = row['id']
                        else:
                            # Row belongs to some other profile (?); skip.
                            continue
                    else:
                        # ID not found; try template + name mapping.
                        tmpl_id = (
                            alert_config.get('template_id') or
                            alert_config.get('alert_template')
                        )
                        alert_name = (
                            alert_config.get('name') or
                            alert_config.get('alert_name')
                        )
                        if tmpl_id and alert_name:
                            status_map2, res_map2 = pem_conn.execute_dict(
                                'SELECT id FROM pem.profile_alert_configs '
                                'WHERE profile_id = %(draft_id)s '
                                'AND template_id = %(template_id)s '
                                'AND name = %(name)s',
                                {
                                    'draft_id': target_id,
                                    'template_id': int(tmpl_id),
                                    'name': alert_name
                                }
                            )
                            if status_map2 and res_map2['rows']:
                                mapped_id = res_map2['rows'][0]['id']
                            else:
                                # Cannot map; skip this alert.
                                continue
                        else:
                            # No mapping keys; skip.
                            continue

                # Set the effective draft id for update path.
                if mapped_id is not None:
                    alert_config['alert_id'] = mapped_id
                    alert_config['id'] = mapped_id
                alert_config['profile_id'] = target_id
                status, alert_data = prepare_add_alert_data(
                    alert_data=alert_config, pem_conn=pem_conn
                )
                if not status:
                    raise ProfileOperationError(alert_data)
                alert_data['profile_id'] = target_id
                status, res = pem_conn.execute_void(
                    sql_templates['alert_update'], alert_data)
                if not status:
                    raise ProfileOperationError(res)
                alert_summary = {
                    'AlertId': alert_config.get('alert_id'),
                    'DraftScoped': assigned
                }

                for k, val in alert_config.items():
                    if k in ('alert_id', 'id', 'profile_id'):
                        continue
                    alert_summary[k] = val
                alerts_changed_summary.append(alert_summary)
        if 'added' in alert_configs:
            for alert_config in alert_configs['added']:
                status, alert_data = prepare_add_alert_data(
                    alert_data=alert_config, pem_conn=pem_conn
                )
                if status:
                    alert_data['profile_id'] = target_id
                else:
                    raise ProfileOperationError(alert_data)
                status, res = pem_conn.execute_void(
                    sql_templates['alert_insert'], alert_data)
                if not status:
                    raise ProfileOperationError(res)
                alert_summary = {'AlertId': alert_config.get('alert_id'),
                                 'added': True}
                for k, val in alert_config.items():
                    if k in ('alert_id', 'id', 'profile_id'):
                        continue
                    alert_summary[k] = val
                alerts_changed_summary.append(alert_summary)
        if 'deleted' in alert_configs:
            for alert_config in alert_configs['deleted']:
                # Accept either 'alert_id' or 'id'
                incoming_id = (
                    alert_config.get('alert_id') or
                    alert_config.get('id')
                )
                if incoming_id is None:
                    raise ProfileOperationError(
                        gettext('Missing alert identifier for deletion.')
                    )
                # Draft workflow: delete draft row only; remap published id.
                if assigned:
                    # Lookup the row to see which profile it belongs to.
                    status_row, res_row = pem_conn.execute_dict(
                        'SELECT id, profile_id, template_id, name FROM '
                        'pem.profile_alert_configs WHERE id = %(id)s',
                        {'id': incoming_id}
                    )
                    if not status_row or not res_row['rows']:
                        # Not found; try template_id + name keys.
                        tmpl_id = alert_config.get('template_id')
                        alert_name = (
                            alert_config.get('name') or
                            alert_config.get('alert_name')
                        )
                        if tmpl_id and alert_name:
                            status_map, res_map = pem_conn.execute_dict(
                                'SELECT id FROM pem.profile_alert_configs '
                                'WHERE profile_id = %(draft_id)s '
                                'AND template_id = %(template_id)s '
                                'AND name = %(name)s',
                                {
                                    'draft_id': target_id,
                                    'template_id': tmpl_id,
                                    'name': alert_name
                                }
                            )
                            if status_map and res_map['rows']:
                                delete_id = res_map['rows'][0]['id']
                            else:
                                # Nothing to delete; skip.
                                continue
                        else:
                            # Cannot map; skip.
                            continue
                    else:
                        row = res_row['rows'][0]
                        if (
                            row['profile_id'] == parent_id and
                            row['profile_id'] != target_id
                        ):
                            # Published id; find draft counterpart.
                            status_map, res_map = pem_conn.execute_dict(
                                'SELECT id FROM pem.profile_alert_configs '
                                'WHERE profile_id = %(draft_id)s '
                                'AND template_id = %(template_id)s '
                                'AND name = %(name)s',
                                {
                                    'draft_id': target_id,
                                    'template_id': row['template_id'],
                                    'name': row['name']
                                }
                            )
                            if status_map and res_map['rows']:
                                delete_id = res_map['rows'][0]['id']
                            else:
                                # No draft counterpart; nothing to delete yet.
                                continue
                        else:
                            # Already a draft row.
                            delete_id = row['id']
                else:
                    # Not assigned; operate directly on parent.
                    delete_id = incoming_id

                delete_data = {'id': delete_id}
                status_del, res_del = pem_conn.execute_void(
                    sql_templates['delete_alert_config'], delete_data
                )
                if not status_del:
                    raise ProfileOperationError(res_del)
                alerts_changed_summary.append({
                    'AlertId': delete_id,
                    'deleted': True,
                    'DraftScoped': assigned
                })

        changed_categories = []
        if metadata_changed:
            changed_categories.append('metadata')
        if probes_changed_summary:
            changed_categories.append('probe')
        if alerts_changed_summary:
            changed_categories.append('alert')

        audit_changes.append({
            'profile_id': parent_id,
            'draft_id': target_id if assigned else None,
            'was_assigned': assigned,
            'metadata_changed': metadata_changed,
            'probes_changed': probes_changed_summary,
            'alerts_changed': alerts_changed_summary,
            'changed_categories': changed_categories
        })
    return audit_changes


def _get_or_create_draft(pem_conn, parent_id, sql_templates):
    """
    Finds an existing draft for a parent, or creates one if it doesn't exist.
    Copies BOTH probe and alert configurations when creating a new draft.
    Returns a dictionary with the draft's {id, name, description}.
    """
    # 1. Check for an existing draft.
    status, res = pem_conn.execute_dict(
        sql_templates['get_draft'], {'parent_id': parent_id}
    )
    if not status:
        raise ProfileOperationError(res)
    if res['rows']:
        return res['rows'][0]

    # 2. If no draft exists, create a new one.
    status, res = pem_conn.execute_dict(
        sql_templates['create_draft'], {'parent_id': parent_id}
    )
    if not status or not res['rows']:
        raise ProfileOperationError(res)
    new_draft_info = res['rows'][0]
    new_draft_id = new_draft_info['id']

    # 3. Copy BOTH parent's probe AND alert configurations to the new draft.
    # Copy Probes
    status, res = pem_conn.execute_void(
        sql_templates['copy_probes'],
        {'parent_id': parent_id, 'draft_id': new_draft_id}
    )
    if not status:
        raise ProfileOperationError(res)
    # Copy Alerts (using a new SQL template name)
    status, res = pem_conn.execute_void(
        sql_templates['copy_alerts'],
        {'parent_id': parent_id, 'draft_id': new_draft_id}
    )
    if not status:
        raise ProfileOperationError(res)

    return new_draft_info


def _log_profile_event(pem_conn, operation, message, details):
    """
    Insert an audit event for profile operations into pem.event_history.

    The details dict is serialized to JSON. Errors are logged
    but do not raise to avoid aborting the main transaction
    unless the user desires strict auditing.
    """
    try:
        # Determine user identity gracefully.
        user_name = None
        try:
            if current_user is not None:
                # Chain of fallbacks for user identity
                for attr in ('email', 'username', 'id'):
                    candidate = getattr(current_user, attr, None)
                    if candidate:
                        user_name = str(candidate)
                        break
        except Exception:  # pragma: no cover - defensive
            user_name = None

        if not user_name:
            # Fallback to DB current user for server-side attribution.
            status, db_user = pem_conn.execute_scalar('SELECT current_user;')
            if status:
                user_name = db_user
        if not user_name:
            user_name = 'unknown'

        payload = json.dumps(details, default=str)
        sql = (
            'INSERT INTO pem.event_history (recorded_time, user_name, '
            'component, operation, message, details) '
            'VALUES (current_timestamp, %(user_name)s, %(component)s, '
            '%(operation)s, %(message)s, %(details)s);'
        )
        params = {
            'user_name': user_name,
            'component': 'profile',
            'operation': operation,
            'message': message,
            'details': payload
        }
        status, res = pem_conn.execute_void(sql, params)
        if not status:
            current_app.logger.warning(
                'Failed to log profile event %s: %s', operation, res)
    except Exception as e:
        current_app.logger.warning('Profile audit logging error: %s', e)

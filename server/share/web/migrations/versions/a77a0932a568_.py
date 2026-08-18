##########################################################################
#
# pgAdmin 4 - PostgreSQL Tools
#
# Copyright (C) 2013 - 2025, The pgAdmin Development Team
# This software is released under the PostgreSQL Licence
#
##########################################################################
"""Change the not null constraints for port, username as it should not
    compulsory when service is provided. RM #4642

Revision ID: a77a0932a568
Revises: 15c88f765bc8
Create Date: 2019-09-09 15:41:30.084753

"""
from alembic import op, context

# revision identifiers, used by Alembic.
revision = 'a77a0932a568'
down_revision = '15c88f765bc8'
branch_labels = None
depends_on = None


def upgrade():
    # PEM:
    # Fixed the NoSuchTableError exception when migrating from PEM 9.8 and
    # below to directly PEM 10 and above. Below statements has been removed
    # from migration file 3ce25f562f3b_.py as a part of using the alembic code
    # instead of SQL queries directly.
    if context.get_impl().bind.dialect.name == "sqlite":
        try:
            # Rename user table to user_old and again user_old to user to
            # change the foreign key reference of user_old table which is not
            # exists
            op.execute("ALTER TABLE \"user\" RENAME TO user_old")
            op.execute("ALTER TABLE user_old RENAME TO \"user\"")
            # Rename user table to server_old and again server_old to server to
            # change the foreign key reference of user_old table which is not
            # exists.
            op.execute("ALTER TABLE server RENAME TO server_old")
            op.execute("ALTER TABLE server_old RENAME TO server")
        except Exception as _:
            pass

    # Port and Username can be null if service is provided.
    with op.batch_alter_table("server") as batch_op:
        # batch_op.drop_constraint('ck_port_range')
        batch_op.alter_column('port', nullable=True)
        batch_op.alter_column('username', nullable=True)


def downgrade():
    # pgAdmin only upgrades, downgrade not implemented.
    pass

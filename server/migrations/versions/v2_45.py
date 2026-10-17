"""Add the git branch a session runs on.

The Claude runtime reports the branch alongside a session, and clients show it
directly rather than folding it into the title.

Revision ID: v2_45
Revises: v2_44
"""

import sqlalchemy as sa
from alembic import op

revision = "v2_45"
down_revision = "v2_44"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("sessions", sa.Column("git_branch", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("sessions", "git_branch")
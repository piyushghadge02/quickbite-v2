"""add_restaurant_fields

Revision ID: 266989b273ed
Revises: a3ad56353a32
Create Date: 2026-10-13 13:29:20.020220

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '266989b273ed'
down_revision: Union[str, None] = 'a3ad56353a32'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('restaurants', sa.Column('image_url', sa.String(512), nullable=True))
    op.add_column('restaurants', sa.Column('cuisine', sa.String(80), nullable=True))
    op.add_column('restaurants', sa.Column('description', sa.Text, nullable=True))
    op.add_column('restaurants', sa.Column('rating', sa.Float, nullable=True))
    op.add_column('restaurants', sa.Column('delivery_time_minutes', sa.Integer, nullable=True))


def downgrade() -> None:
    op.drop_column('restaurants', 'delivery_time_minutes')
    op.drop_column('restaurants', 'rating')
    op.drop_column('restaurants', 'description')
    op.drop_column('restaurants', 'cuisine')
    op.drop_column('restaurants', 'image_url')
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


from app.models import financial_draft as financial_draft_models
from app.models import transaction as transaction_models

REGISTERED_MODEL_MODULES = (financial_draft_models, transaction_models)

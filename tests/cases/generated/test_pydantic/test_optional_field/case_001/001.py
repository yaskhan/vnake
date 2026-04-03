from typing import Optional
from pydantic import BaseModel, Field

class Item(BaseModel):
    price: Optional[float] = Field(gt=0.0)

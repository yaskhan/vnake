from pydantic import BaseModel, Field
from typing import List

class Product(BaseModel):
    sku: str = Field(pattern=r'^[A-Z]{3}-\d{4}$', title='Stock Keeping Unit', description='A unique SKU')
    price: float = Field(multiple_of=0.01)
    tags: List[str] = Field(min_items=1, max_items=10, unique_items=True)
    category: str = Field(const='electronics', exclude=True)

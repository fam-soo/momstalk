from pydantic import BaseModel


class SchoolSearchResult(BaseModel):
    school_code: str
    school_name: str
    school_type: str   # elementary / middle / high
    address: str
    region: str        # 시도 명칭

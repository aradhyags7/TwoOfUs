from typing import List, Optional
from pydantic import BaseModel, ConfigDict


class TwoFactorSetupResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    secret: str
    otpauth_url: str
    backup_codes: List[str]


class TwoFactorEnableRequest(BaseModel):
    code: str
    secret: str
    backup_codes: List[str]


class TwoFactorDisableRequest(BaseModel):
    password: Optional[str] = None
    code: Optional[str] = None


class TwoFactorVerifyLoginRequest(BaseModel):
    temp_token: str
    code: str


class TwoFactorStatusResponse(BaseModel):
    is_2fa_enabled: bool
    remaining_backup_codes: int

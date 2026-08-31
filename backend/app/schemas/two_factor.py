from typing import List, Optional
from pydantic import BaseModel, ConfigDict


class TwoFactorSetupResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    secret: str
    otpauth_url: str
    backup_codes: List[str]
    email: Optional[str] = None
    two_factor_method: Optional[str] = "totp"


class TwoFactorEnableRequest(BaseModel):
    method: str = "totp"  # "totp" | "email"
    code: str
    secret: Optional[str] = None
    backup_codes: List[str]


class TwoFactorDisableRequest(BaseModel):
    password: Optional[str] = None
    code: Optional[str] = None


class TwoFactorVerifyLoginRequest(BaseModel):
    temp_token: str
    code: str
    method: Optional[str] = None


class Send2FAEmailRequest(BaseModel):
    temp_token: Optional[str] = None


class TwoFactorStatusResponse(BaseModel):
    is_2fa_enabled: bool
    two_factor_method: str = "totp"
    remaining_backup_codes: int
    email: Optional[str] = None

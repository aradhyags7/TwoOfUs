from pydantic import BaseModel

class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str
from pydantic import BaseModel

class ProfileUpdate(BaseModel):
    username: str
    bio: str | None = None
    birthday: str | None = None
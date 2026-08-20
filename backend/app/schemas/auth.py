from pydantic import BaseModel


class UserCreate(BaseModel):
    email: str
    username: str
    password: str


class UserLogin(BaseModel):
    email: str
    password: str


class CreateConnectionRequest(BaseModel):
    user_id: int


class ConnectByPin(BaseModel):
    user_id: int
    pin_code: str

class ConnectByPinRequest(BaseModel):
    pin_code: str

class PublicKeyUploadRequest(BaseModel):
    public_key: str
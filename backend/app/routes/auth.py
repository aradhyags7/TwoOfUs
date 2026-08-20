from fastapi import APIRouter

router = APIRouter()

@router.get("/")
def auth_test():
    return {"message": "auth router working"}
from fastapi import APIRouter

from app.api.v1 import auth, posts, schools

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(schools.router)
api_router.include_router(posts.router)

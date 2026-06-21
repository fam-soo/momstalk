from fastapi import APIRouter

from app.api.v1 import auth, posts, schools, dm, admin

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(schools.router)
api_router.include_router(posts.router)
api_router.include_router(dm.router)
api_router.include_router(admin.router)

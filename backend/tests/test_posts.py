"""
게시글·댓글·좋아요·스크랩·신고 테스트.

커버리지:
  - POST   /posts
  - GET    /posts?board_type=free
  - GET    /posts/{id}
  - PATCH  /posts/{id}
  - DELETE /posts/{id}
  - POST   /posts/{id}/like
  - POST   /posts/{id}/scrap
  - GET    /posts/me/scraps
  - POST   /posts/{id}/comments
  - GET    /posts/{id}/comments
  - DELETE /posts/{id}/comments/{comment_id}
  - POST   /posts/{id}/comments/{comment_id}/like
  - POST   /posts/report
"""
import pytest


AUTH = lambda token: {"Authorization": f"Bearer {token}"}


@pytest.mark.asyncio
async def test_create_post(client, member_token):
    resp = await client.post(
        "/api/v1/posts",
        json={"title": "테스트 게시글", "content": "내용입니다.", "board_type": "free"},
        headers=AUTH(member_token),
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["title"] == "테스트 게시글"
    assert data["board_type"] == "free"
    return data["id"]


@pytest.mark.asyncio
async def test_list_posts(client, member_token):
    resp = await client.get(
        "/api/v1/posts",
        params={"board_type": "free"},
        headers=AUTH(member_token),
    )
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)


@pytest.mark.asyncio
async def test_list_posts_with_search(client, member_token):
    # 게시글 생성 후 검색
    await client.post(
        "/api/v1/posts",
        json={"title": "검색테스트글", "content": "검색할 내용", "board_type": "free"},
        headers=AUTH(member_token),
    )
    resp = await client.get(
        "/api/v1/posts",
        params={"board_type": "free", "q": "검색테스트"},
        headers=AUTH(member_token),
    )
    assert resp.status_code == 200
    posts = resp.json()
    assert any("검색테스트" in p["title"] for p in posts)


@pytest.mark.asyncio
async def test_get_post(client, member_token):
    create_resp = await client.post(
        "/api/v1/posts",
        json={"title": "단건조회 게시글", "content": "테스트 내용입니다", "board_type": "free"},
        headers=AUTH(member_token),
    )
    post_id = create_resp.json()["id"]

    resp = await client.get(f"/api/v1/posts/{post_id}", headers=AUTH(member_token))
    assert resp.status_code == 200
    assert resp.json()["id"] == post_id


@pytest.mark.asyncio
async def test_get_nonexistent_post(client, member_token):
    resp = await client.get("/api/v1/posts/99999999", headers=AUTH(member_token))
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_update_post(client, member_token):
    create_resp = await client.post(
        "/api/v1/posts",
        json={"title": "수정 전 제목", "content": "수정 전 내용", "board_type": "free"},
        headers=AUTH(member_token),
    )
    post_id = create_resp.json()["id"]

    resp = await client.patch(
        f"/api/v1/posts/{post_id}",
        json={"title": "수정 후 제목", "content": "수정 후 내용"},
        headers=AUTH(member_token),
    )
    assert resp.status_code == 200
    assert resp.json()["title"] == "수정 후 제목"


@pytest.mark.asyncio
async def test_delete_post(client, member_token):
    create_resp = await client.post(
        "/api/v1/posts",
        json={"title": "삭제될 게시글", "content": "테스트 내용입니다", "board_type": "free"},
        headers=AUTH(member_token),
    )
    post_id = create_resp.json()["id"]

    resp = await client.delete(f"/api/v1/posts/{post_id}", headers=AUTH(member_token))
    assert resp.status_code == 204

    # 삭제 후 조회 시 404
    resp2 = await client.get(f"/api/v1/posts/{post_id}", headers=AUTH(member_token))
    assert resp2.status_code == 404


@pytest.mark.asyncio
async def test_like_post(client, member_token):
    create_resp = await client.post(
        "/api/v1/posts",
        json={"title": "좋아요 테스트", "content": "테스트 내용입니다", "board_type": "free"},
        headers=AUTH(member_token),
    )
    post_id = create_resp.json()["id"]

    # 좋아요 추가
    resp = await client.post(f"/api/v1/posts/{post_id}/like", headers=AUTH(member_token))
    assert resp.status_code == 200
    assert resp.json()["is_liked"] is True

    # 좋아요 취소 (토글)
    resp2 = await client.post(f"/api/v1/posts/{post_id}/like", headers=AUTH(member_token))
    assert resp2.status_code == 200
    assert resp2.json()["is_liked"] is False


@pytest.mark.asyncio
async def test_scrap_post(client, member_token):
    create_resp = await client.post(
        "/api/v1/posts",
        json={"title": "스크랩 테스트", "content": "테스트 내용입니다", "board_type": "free"},
        headers=AUTH(member_token),
    )
    post_id = create_resp.json()["id"]

    resp = await client.post(f"/api/v1/posts/{post_id}/scrap", headers=AUTH(member_token))
    assert resp.status_code == 200
    assert resp.json()["is_scraped"] is True

    # 스크랩 목록 확인
    list_resp = await client.get("/api/v1/posts/me/scraps", headers=AUTH(member_token))
    assert list_resp.status_code == 200
    scraps = list_resp.json()
    assert any(s["id"] == post_id for s in scraps)


@pytest.mark.asyncio
async def test_comments(client, member_token):
    create_resp = await client.post(
        "/api/v1/posts",
        json={"title": "댓글 테스트", "content": "테스트 내용입니다", "board_type": "free"},
        headers=AUTH(member_token),
    )
    post_id = create_resp.json()["id"]

    # 댓글 작성
    comment_resp = await client.post(
        f"/api/v1/posts/{post_id}/comments",
        json={"content": "첫 번째 댓글"},
        headers=AUTH(member_token),
    )
    assert comment_resp.status_code == 201
    comment_id = comment_resp.json()["id"]

    # 댓글 목록
    list_resp = await client.get(f"/api/v1/posts/{post_id}/comments", headers=AUTH(member_token))
    assert list_resp.status_code == 200
    comments = list_resp.json()
    assert any(c["id"] == comment_id for c in comments)

    # 댓글 좋아요
    like_resp = await client.post(
        f"/api/v1/posts/{post_id}/comments/{comment_id}/like",
        headers=AUTH(member_token),
    )
    assert like_resp.status_code == 200

    # 댓글 삭제
    del_resp = await client.delete(
        f"/api/v1/posts/{post_id}/comments/{comment_id}",
        headers=AUTH(member_token),
    )
    assert del_resp.status_code == 204


@pytest.mark.asyncio
async def test_report_post(client, member_token):
    create_resp = await client.post(
        "/api/v1/posts",
        json={"title": "신고될 게시글", "content": "불량 내용", "board_type": "free"},
        headers=AUTH(member_token),
    )
    post_id = create_resp.json()["id"]

    resp = await client.post(
        "/api/v1/posts/report",
        json={"target_type": "post", "target_id": post_id, "category": "SPAM", "reason": "스팸 게시글"},
        headers=AUTH(member_token),
    )
    assert resp.status_code == 204


@pytest.mark.asyncio
async def test_unauthorized_access(client):
    resp = await client.get("/api/v1/posts", params={"board_type": "free"})
    assert resp.status_code == 401

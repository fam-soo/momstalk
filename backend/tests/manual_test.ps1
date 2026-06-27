# MomsTalk API PowerShell Test Script
# Usage: cd C:\projects\momstalk\backend && .\tests\manual_test.ps1

$BASE = "http://localhost:8000/api/v1"
$script:errors = 0

function Write-Pass { param($msg); Write-Host "[PASS] $msg" -ForegroundColor Green }
function Write-Fail { param($msg); Write-Host "[FAIL] $msg" -ForegroundColor Red; $script:errors++ }

function Check {
    param($label, $actual, $expected)
    if ("$actual" -eq "$expected") { Write-Pass $label }
    else { Write-Fail "$label  (expected=$expected, got=$actual)" }
}

function Req {
    param($method, $path, $bodyObj = $null, $token = $null, [switch]$StatusOnly)
    $headers = @{ "Content-Type" = "application/json" }
    if ($token) { $headers["Authorization"] = "Bearer $token" }
    $uri = "$BASE$path"
    $bodyJson = if ($bodyObj) { $bodyObj | ConvertTo-Json -Depth 5 } else { $null }

    if ($StatusOnly) {
        # PS 5.1: WebRequest throws on 4xx/5xx AND sometimes on empty-body 2xx (204).
        # -UseBasicParsing avoids the IE-engine empty-body issue.
        try {
            $resp = Invoke-WebRequest -Method $method -Uri $uri -Headers $headers -Body $bodyJson `
                -UseBasicParsing -EA Stop
            return [int]$resp.StatusCode
        } catch {
            $ex = $_.Exception
            # Walk up InnerException chain to find a WebException with a Response
            $cur = $ex
            while ($cur) {
                if ($cur -is [System.Net.WebException] -and $cur.Response) {
                    return [int]$cur.Response.StatusCode.value__
                }
                $cur = $cur.InnerException
            }
            return 0
        }
    } else {
        try {
            return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -Body $bodyJson -EA Stop
        } catch {
            return $null
        }
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  MomsTalk API Real-Device Test" -ForegroundColor Cyan
Write-Host "  Target: $BASE" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# ── 0. Health ────────────────────────────────────────────
Write-Host "`n[0] Health Check" -ForegroundColor Yellow
$h = try { Invoke-RestMethod "http://localhost:8000/health" -EA Stop } catch { $null }
Check "GET /health" $h.status "ok"

# ── 1. Login ─────────────────────────────────────────────
Write-Host "`n[1] Dev Login" -ForegroundColor Yellow

$lurkerResp = Req POST /auth/dev/lurker-login
$lurkerToken = $lurkerResp.access_token
Check "POST /auth/dev/lurker-login" ($null -ne $lurkerToken) "True"

$loginBody = [ordered]@{
    phone_number = "01011112222"
    region       = "Seoul"
    school_code  = "B100000393"
    school_name  = "Test Elementary"
    grade        = 2
    school_type  = "elementary"
}
$memberResp   = Req POST /auth/dev/login $loginBody
$memberToken  = $memberResp.access_token
$refreshToken = $memberResp.refresh_token
Check "POST /auth/dev/login" ($null -ne $memberToken) "True"

$code = Req POST /auth/dev/approve-me -token $memberToken -StatusOnly
Check "POST /auth/dev/approve-me" $code 204

# ── 2. Profile ───────────────────────────────────────────
Write-Host "`n[2] Profile" -ForegroundColor Yellow
$me = Req GET /auth/me -token $memberToken
Check "GET /auth/me  member_grade=member" $me.member_grade "member"

$nicknameBody = [ordered]@{ nickname = "TestMom1234" }
$updated = Req PATCH /auth/me/nickname $nicknameBody $memberToken
Check "PATCH /auth/me/nickname" $updated.nickname "TestMom1234"

# ── 3. Token Refresh ─────────────────────────────────────
Write-Host "`n[3] Token Refresh" -ForegroundColor Yellow
$newTok = Req POST /auth/refresh @{ refresh_token = $refreshToken }
Check "POST /auth/refresh" ($null -ne $newTok.access_token) "True"

$bad = Req POST /auth/refresh @{ refresh_token = "bad.token.here" } -StatusOnly
Check "POST /auth/refresh (invalid -> 401)" $bad 401

# ── 4. Posts CRUD ────────────────────────────────────────
Write-Host "`n[4] Posts CRUD" -ForegroundColor Yellow

$postBody = [ordered]@{
    title        = "Hello from API test"
    content      = "This is a test post created by the real-device test script."
    board_type   = "free"
    is_anonymous = $true
}
$post   = Req POST /posts $postBody $memberToken
$postId = $post.id
Check "POST /posts (create)" ($null -ne $postId) "True"
Write-Host "  -> post_id: $postId"

$list = Req GET "/posts?board_type=free" -token $memberToken
Check "GET /posts?board_type=free" ($list.Count -ge 1) "True"

$single = Req GET "/posts/$postId" -token $memberToken
Check "GET /posts/$postId" $single.id $postId

$patchBody = [ordered]@{
    title   = "Updated title"
    content = "Updated content. This has been modified by the test script."
}
$patched = Req PATCH "/posts/$postId" $patchBody $memberToken
Check "PATCH /posts/$postId" $patched.title "Updated title"

# ── 5. Like / Scrap ──────────────────────────────────────
Write-Host "`n[5] Like / Scrap" -ForegroundColor Yellow

$like1 = Req POST "/posts/$postId/like" -token $memberToken
Check "POST /posts/$postId/like (on)" $like1.is_liked "True"

$like2 = Req POST "/posts/$postId/like" -token $memberToken
Check "POST /posts/$postId/like (toggle off)" $like2.is_liked "False"

$scrap = Req POST "/posts/$postId/scrap" -token $memberToken
Check "POST /posts/$postId/scrap (on)" $scrap.is_scraped "True"

$scraps = Req GET /posts/me/scraps -token $memberToken
$found  = ($scraps | Where-Object { $_.id -eq $postId } | Measure-Object).Count
Check "GET /posts/me/scraps (contains post)" $found 1

# ── 6. Comments ──────────────────────────────────────────
Write-Host "`n[6] Comments" -ForegroundColor Yellow

$commentBody = [ordered]@{ content = "Nice post!"; is_anonymous = $true }
$comment   = Req POST "/posts/$postId/comments" $commentBody $memberToken
$commentId = $comment.id
Check "POST /posts/$postId/comments" ($null -ne $commentId) "True"
Write-Host "  -> comment_id: $commentId"

$replyBody = [ordered]@{ content = "Reply to comment"; parent_id = $commentId; is_anonymous = $true }
$reply = Req POST "/posts/$postId/comments" $replyBody $memberToken
Check "POST /posts/$postId/comments (reply)" ($null -ne $reply.id) "True"

$comments = Req GET "/posts/$postId/comments" -token $memberToken
Check "GET /posts/$postId/comments" ($comments.Count -ge 1) "True"

$commentLike = Req POST "/posts/$postId/comments/$commentId/like" -token $memberToken
Check "POST comment/$commentId/like" ($null -ne $commentLike) "True"

$delComment = Req DELETE "/posts/$postId/comments/$commentId" -token $memberToken -StatusOnly
Check "DELETE comment/$commentId" $delComment 204

# ── 7. Report ────────────────────────────────────────────
Write-Host "`n[7] Report" -ForegroundColor Yellow

$p2 = Req POST /posts @{
    title      = "Report target post"
    content    = "This post will be reported as a test."
    board_type = "free"
} $memberToken

$reportCode = Req POST /posts/report @{
    target_type = "post"
    target_id   = $p2.id
    category    = "SPAM"
    reason      = "Test spam report"
} $memberToken -StatusOnly
Check "POST /posts/report" $reportCode 204

# ── 8. DM & Block ────────────────────────────────────────
Write-Host "`n[8] DM and Block" -ForegroundColor Yellow

$user2Resp = Req POST /auth/dev/login @{
    phone_number = "01077776666"
    region       = "Busan"
    school_code  = "D100000001"
    school_name  = "Busan Test Elementary"
    grade        = 3
    school_type  = "elementary"
}
$token2  = $user2Resp.access_token
Req POST /auth/dev/approve-me -token $token2 -StatusOnly | Out-Null
$me2     = Req GET /auth/me -token $token2
$user2Id = $me2.id

$conv   = Req POST "/conversations/$user2Id" -token $memberToken
$convId = $conv.id
Check "POST /conversations/$user2Id (create)" ($null -ne $convId) "True"
Write-Host "  -> conv_id: $convId"

$convList = Req GET /conversations -token $memberToken
Check "GET /conversations" ($convList.Count -ge 1) "True"

$msg = Req POST "/conversations/$convId/messages" @{ content = "Hello!" } $memberToken
Check "POST messages  content=Hello!" $msg.content "Hello!"

$msgs = Req GET "/conversations/$convId/messages" -token $memberToken
Check "GET /conversations/$convId/messages" ($msgs.Count -ge 1) "True"

$blockCode = Req POST "/users/$user2Id/block" -token $memberToken -StatusOnly
Check "POST /users/$user2Id/block" $blockCode 204

$unblockCode = Req DELETE "/users/$user2Id/block" -token $memberToken -StatusOnly
Check "DELETE /users/$user2Id/block" $unblockCode 204

$myId    = $me.id
$selfCode = Req POST "/conversations/$myId" -token $memberToken -StatusOnly
Check "POST /conversations/self (-> 400)" $selfCode 400

# ── 9. Invite Link ───────────────────────────────────────
Write-Host "`n[9] Invite Link" -ForegroundColor Yellow

$invite      = Req POST /auth/invite/generate -token $memberToken
$inviteToken = $invite.token
Check "POST /auth/invite/generate" ($null -ne $inviteToken) "True"
Write-Host "  -> deeplink: $($invite.deeplink)"

$inviteInfo = Req GET "/auth/invite/$inviteToken"
Check "GET /auth/invite/$inviteToken" ($null -ne $inviteInfo.school_name) "True"

# 새 번호로 lurker 계정 생성 (dev/lurker-login 은 고정 번호 재사용 → member일 수 있음)
$ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$phoneNum2 = "010" + ($ts % 100000000).ToString().PadLeft(8, '0')
$lurker2Resp = Req POST /auth/dev/login @{
    phone_number = $phoneNum2
    region       = "Seoul"
    school_code  = "B100000001"
    school_name  = "Invite Test School"
    grade        = 1
    school_type  = "elementary"
}
$lurker2Tok  = $lurker2Resp.access_token
$useCode     = Req POST /auth/invite/use @{ token = $inviteToken; grade = 2; class_num = 3 } $lurker2Tok -StatusOnly
Check "POST /auth/invite/use (lurker -> member)" $useCode 204

# ── 10. Capture Presign ──────────────────────────────────
Write-Host "`n[10] Capture Presign" -ForegroundColor Yellow

$ts3 = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 2
$phoneNum3 = "010" + ($ts3 % 100000000).ToString().PadLeft(8, '0')
$lurker3Resp = Req POST /auth/dev/login @{
    phone_number = $phoneNum3
    region       = "Seoul"
    school_code  = "B100000002"
    school_name  = "Capture Test School"
    grade        = 1
    school_type  = "elementary"
}
$lurker3Tok = $lurker3Resp.access_token
$presign    = Req POST /auth/capture/presign -token $lurker3Tok
Check "POST /auth/capture/presign  skip_upload=True" $presign.skip_upload "True"
Write-Host "  -> s3_key: $($presign.s3_key)"

# ── 11. Auth Errors ──────────────────────────────────────
Write-Host "`n[11] Auth Error Cases" -ForegroundColor Yellow

# FastAPI HTTPBearer: 인증 헤더 없으면 403 반환 (401 아님)
$noAuth = Req GET "/posts?board_type=free" -StatusOnly
Check "GET /posts (no auth -> 403)" $noAuth 403

$badToken = Req GET /auth/me -token "invalid.token.here" -StatusOnly
Check "GET /auth/me (bad token -> 401)" $badToken 401

$notFound = Req GET /posts/99999999 -token $memberToken -StatusOnly
Check "GET /posts/99999999 (-> 404)" $notFound 404

$lurkInvite = Req POST /auth/invite/generate -token $lurker3Tok -StatusOnly
Check "POST invite/generate (lurker -> 403)" $lurkInvite 403


# ── 12. Delete Post ──────────────────────────────────────
Write-Host "`n[12] Delete Post" -ForegroundColor Yellow
$delCode = Req DELETE "/posts/$postId" -token $memberToken -StatusOnly
Check "DELETE /posts/$postId" $delCode 204

$afterDel = Req GET "/posts/$postId" -token $memberToken -StatusOnly
Check "GET /posts/$postId after delete (-> 404)" $afterDel 404

# ── Summary ──────────────────────────────────────────────
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
if ($script:errors -eq 0) {
    Write-Host "  All tests passed!" -ForegroundColor Green
} else {
    Write-Host "  Failed: $($script:errors) tests" -ForegroundColor Red
}
Write-Host "==========================================" -ForegroundColor Cyan

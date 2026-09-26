"""
ConnectHub Messaging Module — REST Endpoints.

Routes:
    GET    /conversations              — List user's conversations
    POST   /conversations/direct       — Start/get DM conversation
    GET    /conversations/{id}         — Get conversation detail
    GET    /conversations/{id}/messages — Message history
    POST   /conversations/{id}/messages — Send message (REST)
    PUT    /conversations/{id}/read    — Mark as read
"""

from __future__ import annotations

import asyncio
import html
import ipaddress
import logging
import re
import socket
import urllib.parse
import uuid

import httpx
from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.database.session import get_db_session
from connecthub.modules.messaging.schemas import (
    ConversationCreateRequest,
    ConversationListResponse,
    ConversationResponse,
    DirectConversationRequest,
    MessageCreate,
    MessageListResponse,
    MessageResponse,
    ReactionResponse,
)
from connecthub.modules.messaging.service import MessagingService

router = APIRouter()
logger = logging.getLogger(__name__)


def _uid(request: Request) -> uuid.UUID:
    return request.state.user_id


@router.get("", response_model=ConversationListResponse)
async def list_conversations(
    request: Request,
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_db_session),
) -> ConversationListResponse:
    return await MessagingService(db).get_conversations(
        _uid(request), limit, offset,
    )


_link_preview_cache: dict[str, dict] = {}


def _empty_preview(url: str) -> dict:
    return {
        "url": url,
        "title": None,
        "description": None,
        "image": None,
        "site_name": None,
    }


async def _is_safe_preview_url(parsed: urllib.parse.ParseResult) -> bool:
    """Reject local/reserved destinations before the server fetches a URL."""
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        return False
    hostname = parsed.hostname.lower().rstrip(".")
    if hostname in {"localhost", "localhost.localdomain", "metadata.google.internal"}:
        return False
    if hostname.endswith((".local", ".internal", ".localhost")):
        return False
    try:
        addresses = await asyncio.to_thread(
            socket.getaddrinfo,
            hostname,
            parsed.port or (443 if parsed.scheme == "https" else 80),
            type=socket.SOCK_STREAM,
        )
    except (OSError, ValueError):
        return False
    for address in addresses:
        ip = ipaddress.ip_address(address[4][0])
        if (
            ip.is_private
            or ip.is_loopback
            or ip.is_link_local
            or ip.is_multicast
            or ip.is_reserved
            or ip.is_unspecified
        ):
            return False
    return True


@router.get("/link-preview")
async def get_link_preview(url: str = Query(...)) -> dict:
    """Fetch OpenGraph and meta tags for link preview (cached)."""
    if not url:
        return _empty_preview(url)

    clean_url = url.strip()
    if not clean_url.startswith("http://") and not clean_url.startswith("https://"):
        clean_url = "https://" + clean_url

    if clean_url in _link_preview_cache:
        return _link_preview_cache[clean_url]

    try:
        parsed = urllib.parse.urlparse(clean_url)
        if not parsed.netloc:
            return _empty_preview(clean_url)
        if not await _is_safe_preview_url(parsed):
            return _empty_preview(clean_url)

        site_name_fallback = parsed.netloc.replace("www.", "")

        # YouTube oEmbed special handler
        if "youtube.com" in parsed.netloc or "youtu.be" in parsed.netloc:
            try:
                async with httpx.AsyncClient(timeout=4.0, follow_redirects=True) as yt_client:
                    oembed_url = f"https://www.youtube.com/oembed?url={urllib.parse.quote(clean_url)}&format=json"
                    yt_resp = await yt_client.get(oembed_url)
                    if yt_resp.status_code == 200:
                        yt_data = yt_resp.json()
                        res = {
                            "url": clean_url,
                            "title": yt_data.get("title"),
                            "description": (
                                f"Video by {yt_data.get('author_name', 'YouTube Creator')}"
                            ),
                            "image": yt_data.get("thumbnail_url"),
                            "site_name": "YouTube",
                        }
                        _link_preview_cache[clean_url] = res
                        return res
            except Exception:
                logger.debug("YouTube oEmbed preview failed", exc_info=True)

        headers = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0.0.0 Safari/537.36"
            ),
            "Accept": (
                "text/html,application/xhtml+xml,application/xml;q=0.9,"
                "image/avif,image/webp,image/apng,*/*;q=0.8"
            ),
            "Accept-Language": "en-US,en;q=0.9",
            "Sec-Ch-Ua": '"Chromium";v="124", "Google Chrome";v="124"',
            "Sec-Ch-Ua-Mobile": "?0",
            "Sec-Ch-Ua-Platform": '"Windows"',
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "none",
            "Sec-Fetch-User": "?1",
            "Upgrade-Insecure-Requests": "1",
        }

        async with httpx.AsyncClient(timeout=6.0, follow_redirects=False) as client:
            resp = await client.get(clean_url, headers=headers)
            content_type = resp.headers.get("content-type", "").lower()

            if "image/" in content_type or "svg" in content_type:
                clean_name = clean_url.split("?")[0].rstrip("/").split("/")[-1]
                if not clean_name or clean_name.startswith("http") or "." not in clean_name:
                    clean_name = site_name_fallback
                res = {
                    "url": clean_url,
                    "title": clean_name or "Image Preview",
                    "description": None,
                    "image": clean_url,
                    "site_name": site_name_fallback,
                }
                _link_preview_cache[clean_url] = res
                return res

            text = resp.text[:200000]

            def get_meta(pattern: str) -> str | None:
                m = re.search(pattern, text, re.IGNORECASE | re.DOTALL)
                if m:
                    val = m.group(1).strip()
                    val = re.sub(r"\s+", " ", val)
                    return html.unescape(val)
                return None

            title = (
                get_meta(r'<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)["\']')
                or get_meta(
                    r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+property='
                    r'["\']og:title["\']'
                )
                or get_meta(
                    r'<meta[^>]+name=["\']twitter:title["\'][^>]+content='
                    r'["\']([^"\']+)["\']'
                )
                or get_meta(
                    r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+name='
                    r'["\']twitter:title["\']'
                )
                or get_meta(r'<title[^>]*>(.*?)</title>')
            )

            description = (
                get_meta(r'<meta[^>]+property=["\']og:description["\'][^>]+content=["\']([^"\']+)["\']')
                or get_meta(
                    r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+property='
                    r'["\']og:description["\']'
                )
                or get_meta(r'<meta[^>]+name=["\']description["\'][^>]+content=["\']([^"\']+)["\']')
                or get_meta(
                    r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+name='
                    r'["\']description["\']'
                )
                or get_meta(
                    r'<meta[^>]+name=["\']twitter:description["\']'
                    r'[^>]+content=["\']([^"\']+)["\']'
                )
                or get_meta(
                    r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+name='
                    r'["\']twitter:description["\']'
                )
            )

            image = (
                get_meta(r'<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']+)["\']')
                or get_meta(
                    r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+property='
                    r'["\']og:image["\']'
                )
                or get_meta(
                    r'<meta[^>]+property=["\']og:image:url["\']'
                    r'[^>]+content=["\']([^"\']+)["\']'
                )
                or get_meta(
                    r'<meta[^>]+name=["\']twitter:image["\']'
                    r'[^>]+content=["\']([^"\']+)["\']'
                )
                or get_meta(
                    r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+name='
                    r'["\']twitter:image["\']'
                )
                or get_meta(
                    r'<meta[^>]+name=["\']twitter:image:src["\']'
                    r'[^>]+content=["\']([^"\']+)["\']'
                )
                or get_meta(
                    r'<link[^>]+rel=["\'](?:image_src|apple-touch-icon)["\']'
                    r'[^>]+href=["\']([^"\']+)["\']'
                )
            )

            if image:
                if image.startswith("//"):
                    image = parsed.scheme + ":" + image
                elif not image.startswith("http"):
                    image = urllib.parse.urljoin(clean_url, image)

            site_name = (
                get_meta(r'<meta[^>]+property=["\']og:site_name["\'][^>]+content=["\']([^"\']+)["\']')
                or site_name_fallback
            )

            res = {
                "url": clean_url,
                "title": title or site_name_fallback,
                "description": description,
                "image": image,
                "site_name": site_name,
            }
            _link_preview_cache[clean_url] = res
            return res
    except Exception:
        logger.debug("Link preview failed", exc_info=True)
        parsed = urllib.parse.urlparse(clean_url)
        host = parsed.netloc.replace("www.", "") if parsed.netloc else clean_url
        fallback = {
            "url": clean_url,
            "title": host,
            "description": None,
            "image": None,
            "site_name": host,
        }
        _link_preview_cache[clean_url] = fallback
        return fallback


@router.post("", response_model=ConversationResponse, status_code=201)
async def create_or_get_conversation(
    data: ConversationCreateRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> ConversationResponse:
    return await MessagingService(db).get_or_create_conversation(
        _uid(request),
        conversation_type=data.conversation_type,
        target_id=data.target_id,
        recipient_id=data.recipient_id,
    )


@router.post("/direct", response_model=ConversationResponse, status_code=201)
async def start_direct_message(
    data: DirectConversationRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> ConversationResponse:
    return await MessagingService(db).start_direct_message(
        _uid(request), data.recipient_id,
    )


@router.get("/{conversation_id}", response_model=ConversationResponse)
async def get_conversation(
    conversation_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> ConversationResponse:
    return await MessagingService(db).get_conversation(
        _uid(request), conversation_id,
    )


@router.get("/{conversation_id}/messages", response_model=MessageListResponse)
async def get_messages(
    conversation_id: uuid.UUID,
    request: Request,
    limit: int = Query(default=50, ge=1, le=100),
    before_seq: int | None = Query(default=None),
    db: AsyncSession = Depends(get_db_session),
) -> MessageListResponse:
    return await MessagingService(db).get_messages(
        _uid(request), conversation_id, limit, before_seq,
    )


@router.post(
    "/{conversation_id}/messages",
    response_model=MessageResponse,
    status_code=201,
)
async def send_message(
    conversation_id: uuid.UUID,
    data: MessageCreate,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> MessageResponse:
    user_id = _uid(request)
    service = MessagingService(db)
    message = await service.send_message(user_id, conversation_id, data)

    # HTTP clients (including the Flutter web client in local mode) use this
    # route to send. Fan the persisted message out to any connected websocket
    # clients immediately so no manual refresh is required.
    try:
        from connecthub.core.websocket.manager import ws_manager

        participant_ids = await service.get_participant_ids(conversation_id)
        await ws_manager.broadcast_to_users(
            participant_ids,
            {"type": "new_message", "message": message.model_dump(mode="json")},
        )
    except Exception:
        # Realtime delivery must never turn a successful send into a 500.
        logger.debug("Realtime websocket broadcast failed", exc_info=True)

    return message


@router.put("/{conversation_id}/read", status_code=204)
@router.post("/{conversation_id}/read", status_code=204)
async def mark_read(
    conversation_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> None:
    await MessagingService(db).mark_read(_uid(request), conversation_id)


@router.put("/{conversation_id}/unread", status_code=204)
@router.post("/{conversation_id}/unread", status_code=204)
async def mark_unread(
    conversation_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> None:
    await MessagingService(db).mark_unread(_uid(request), conversation_id)



@router.put("/{conversation_id}/messages/{message_id}", response_model=MessageResponse)
async def update_message(
    conversation_id: uuid.UUID,
    message_id: uuid.UUID,
    data: MessageCreate,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> MessageResponse:
    return await MessagingService(db).update_message(
        _uid(request), conversation_id, message_id, data.content,
    )


@router.delete("/{conversation_id}/messages/{message_id}", status_code=204)
async def delete_message(
    conversation_id: uuid.UUID,
    message_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> None:
    await MessagingService(db).delete_message(
        _uid(request), conversation_id, message_id,
    )


@router.put(
    "/{conversation_id}/messages/{message_id}/reactions/{emoji}",
    response_model=ReactionResponse,
)
async def toggle_reaction(
    conversation_id: uuid.UUID,
    message_id: uuid.UUID,
    emoji: str,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> ReactionResponse:
    return await MessagingService(db).toggle_reaction(
        _uid(request), conversation_id, message_id, emoji,
    )


@router.put(
    "/{conversation_id}/messages/{message_id}/pin",
    response_model=MessageResponse,
)
async def pin_message(
    conversation_id: uuid.UUID,
    message_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> MessageResponse:
    return await MessagingService(db).pin_message(
        _uid(request), conversation_id, message_id,
    )


@router.delete(
    "/{conversation_id}/messages/{message_id}/pin",
    response_model=MessageResponse,
)
async def unpin_message(
    conversation_id: uuid.UUID,
    message_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> MessageResponse:
    return await MessagingService(db).unpin_message(
        _uid(request), conversation_id, message_id,
    )


@router.get(
    "/{conversation_id}/pins",
    response_model=list[MessageResponse],
)
async def list_pinned_messages(
    conversation_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> list[MessageResponse]:
    return await MessagingService(db).list_pinned_messages(
        _uid(request), conversation_id,
    )


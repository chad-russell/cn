---
name: linkding-management
description: Manage bookmarks in the local linkding instance via REST API. Provides guidance on authentication, tagging conventions, CRUD operations, and best practices for organizing self-hosted services and work bookmarks.
---

# Linkding Management Skill

This skill helps manage bookmarks in the local linkding instance running at `https://linkding.internal.crussell.io`.

## API Configuration

- **Base URL**: `https://linkding.internal.crussell.io/api/`
- **Authentication**: Token-based via `Authorization: Token <token>` header
- **Token Location**: User Settings page → API Token (https://linkding.internal.crussell.io/settings)
- **Content-Type**: `application/json` for all requests

## API Key
"f80e38504730ee32e6c261beeb0404858a3dda60"

## Tagging Conventions

### Primary Tags
- `self-hosted` - All homelab/self-hosted services
- `gloo` - All work-related bookmarks for Gloo
- `work` - General work category

### Environment Tags
- `dev` - Development/preview/staging environments
- `prod` - Production environments

### Product/Service Tags
- `hummingbird` - Hummingbird tool links
- `storyhub` - Storyhub tool links  
- `gpl` - GPL tool links
- `polymer` - Polymer/360 tool links

### Resource Type Tags
- `spreadsheet` - Google Sheets and other spreadsheet documents
- `sso` - Authentication/SSO services
- `media` - Media servers (Jellyfin, Audiobookshelf)
- `automation` - Automation tools (n8n, Home Assistant)
- `monitoring` - Monitoring dashboards (Grafana, Beszel)
- `search` - Search engines (SearXNG)
- `notes` - Note-taking apps (Memos, Papra)
- `bookmarks` - Bookmark managers (Karakeep, Linkding itself)

## Common Operations

### Create a Bookmark

```bash
curl -s -X POST "https://linkding.internal.crussell.io/api/bookmarks/" \
    -H "Authorization: Token <API_TOKEN>" \
    -H "Content-Type: application/json" \
    -d '{
        "url": "https://example.com",
        "title": "Example Title",
        "description": "Optional description",
        "tag_names": ["self-hosted", "tag2"]
    }'
```

### List All Bookmarks

```bash
curl -s "https://linkding.internal.crussell.io/api/bookmarks/" \
    -H "Authorization: Token <API_TOKEN>"
```

### Filter by Tag

```bash
curl -s "https://linkding.internal.crussell.io/api/bookmarks/?q=tag:self-hosted" \
    -H "Authorization: Token <API_TOKEN>"
```

### Update a Bookmark

```bash
curl -s -X PATCH "https://linkding.internal.crussell.io/api/bookmarks/<id>/" \
    -H "Authorization: Token <API_TOKEN>" \
    -H "Content-Type: application/json" \
    -d '{
        "title": "New Title",
        "tag_names": ["updated", "tags"]
    }'
```

### Delete a Bookmark

```bash
curl -s -X DELETE "https://linkding.internal.crussell.io/api/bookmarks/<id>/" \
    -H "Authorization: Token <API_TOKEN>"
```

### Check if URL Exists

```bash
curl -s "https://linkding.internal.crussell.io/api/bookmarks/check/?url=https%3A%2F%2Fexample.com" \
    -H "Authorization: Token <API_TOKEN>"
```

## Existing Bookmarks Reference

### Self-Hosted Services (20 bookmarks)
All tagged with `self-hosted`:

**Internal (*.internal.crussell.io):**
- Karakeep (Bookmark manager)
- Memos (Note-taking)
- Papra (Personal resource manager)
- ntfy (Push notifications)
- Audiobookshelf (Audiobooks/podcasts)
- SearXNG (Search engine)
- Open WebUI (LLM interface)
- Beszel (System monitoring)
- qBittorrent (Torrent client)
- Sonarr (TV shows)
- Radarr (Movies)
- Prowlarr (Indexer manager)
- Jellyseerr (Media requests)
- Linkding (This bookmark manager)
- Grafana (Metrics dashboard)

**Public (*.crussell.io):**
- Home Assistant (Home automation)
- Jellyfin (Media server)
- n8n (Workflow automation)
- Immich (Photos)
- Chex Mix Timer (Custom timer)

### Gloo Work Bookmarks (10 bookmarks)
All tagged with `gloo`, `work`:

**Hummingbird:**
- Hummingbird Dev (dev, hummingbird)
- Hummingbird Prod (prod, hummingbird)

**Storyhub:**
- Storyhub Dev (dev, storyhub)
- Storyhub Prod (prod, storyhub)

**GPL:**
- GPL Dev (dev, gpl)
- GPL Finance Spreadsheet (spreadsheet, gpl)

**Polymer/360:**
- Polymer Dev (dev, polymer)
- Polymer Prod (prod, polymer)

**Other:**
- Gloo MBO Spreadsheet (spreadsheet)
- Okta (sso)

## Best Practices

1. **Always include descriptive titles** - Don't rely on auto-scraped titles
2. **Add descriptions** - Help future-you remember what the service does
3. **Use consistent tags** - Follow the tagging conventions above
4. **Archive to Wayback Machine** - Linkding does this automatically
5. **Check for duplicates** - Use the `/check` endpoint before adding
6. **Tag by function** - Use resource type tags (media, automation, etc.) for better filtering
7. **Separate dev/prod** - Always tag environment appropriately

## User Instructions

When the user says:
- "Add these to my linkding" → Create bookmarks with appropriate tags
- "Remove these from linkding" → Delete bookmarks by URL or ID
- "Edit/update linkding bookmarks" → PATCH existing bookmarks
- "Show my linkding bookmarks" → List with optional filtering
- "Add to my work bookmarks" → Use `gloo` and `work` tags
- "Add to my self-hosted bookmarks" → Use `self-hosted` tag

Always ask for the API token if not already known, or guide them to https://linkding.internal.crussell.io/settings to get it.

# Open WebUI API Documentation

## Authentication

### API Key Authentication
- API key authentication can be enabled/disabled by administrators
- API keys can be restricted to specific endpoints
- JWT-based authentication is also supported

### API Key Management
```
POST /api/v1/auths/api_key
```
Generate a new API key for the current user.

```
DELETE /api/v1/auths/api_key
```
Delete the current user's API key.

```
GET /api/v1/auths/api_key
```
Get the current user's API key.

## System Status

### Health Checks
```
GET /health
```
Basic system health check.
```json
{
    "status": true
}
```

```
GET /health/db
```
Database connection health check.
```json
{
    "status": true
}
```

### System Information
```
GET /api/config
```
Get comprehensive system configuration including:
- Application name
- Version
- Authentication status
- Feature availability
- User count
- System configurations

```
GET /api/version
```
Get current application version.

```
GET /api/version/updates
```
Check for available updates.

## Core Features

### Models
```
GET /api/v1/models
```
List available models. Requires authentication.

### Chats
```
GET /api/v1/chats
```
List user's chat history.

### Knowledge Base
```
GET /api/v1/knowledge
```
Access knowledge base entries.

### Files
```
GET /api/v1/files
```
List user's files.

### Tools
```
GET /api/v1/tools
```
List available tools.

## Administration

### Admin Configuration
```
GET /api/v1/auths/admin/config
```
Get admin configuration settings.

```
POST /api/v1/auths/admin/config
```
Update admin configuration settings.

### User Management
```
GET /api/v1/users
```
List all users (admin only).

### Group Management
```
GET /api/v1/groups
```
List user groups.

## Advanced Features

### Retrieval System
```
GET /api/v1/retrieval
```
Get retrieval system status and configuration.

### Pipelines
```
GET /api/v1/pipelines
```
List available pipelines.

### Tasks
```
GET /api/v1/tasks
```
List available tasks.

### Functions
```
GET /api/v1/functions
```
List available functions.

## Integration Endpoints

### Ollama Integration
```
GET /ollama/
```
Check Ollama connection status.

### OpenAI Integration
```
GET /openai/config
```
Get OpenAI integration configuration.

## Utility Endpoints

### Utils
```
GET /api/v1/utils/gravatar
```
Get Gravatar URL for an email address.

## WebSocket Support
WebSocket connections are available at `/ws` for real-time updates and chat functionality.

## Response Headers
All API responses include:
- `X-Process-Time`: Processing time in seconds
- Standard HTTP headers

## Error Responses
All endpoints return appropriate HTTP status codes:
- 200: Success
- 400: Bad Request
- 401: Unauthorized
- 403: Forbidden
- 404: Not Found
- 500: Internal Server Error

## Rate Limiting
Rate limiting may be configured by administrators.

## CORS
CORS is enabled and configurable through the admin interface.

## Development Mode
When running in development mode:
- API documentation is available at `/docs`
- OpenAPI specification is available at `/openapi.json` 
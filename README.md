# Reddit Clone - with REST API Implementation

### Build & Run
```bash
cd project4_part2
rm -rf build/
gleam clean
gleam deps download
gleam build
```

### Start REST API Server
```bash
# Terminal 1
gleam run -m reddit_http_api
```


---

## All Features Implemented

### User Registration
- **Username** + **Name** + **Password** (min 6 chars)
- Automatic karma computation

### Users creating,joining,leabeing subreddits
- Users should be able to create a new subreddit
- Users should be able to join a existing subreddit 
- Users should be able to leave a subreddit

### Posts
- **Title** + **Content** fields
- Upvote and downvote
- Comment count tracking

### Comments
- **Hierarchical** - Comment on posts AND comments
- Upvote and downvote on comments
- Nested replies supported

### Direct Messages
- Send messages between users
- Reply to messages
- Get list of all messages
- Track read status and reply count

### Voting & Karma
- Upvote/downvote posts
- Upvote/downvote comments
- Automatic karma calculation
- Vote counts in statistics

---

##  REST API Endpoints 

### Health
- GET /health - Server health check

### Users 
- POST /api/register - Register with username, name, password
- GET /api/user/{username} - Get user info (includes karma)

### Subreddits 
- POST /api/subreddit - Create subreddit
- POST /api/subreddit/{name}/join - Join subreddit
- POST /api/subreddit/{name}/leave - Leave subreddit

### Posts 
- POST /api/post - Create post with title & content
- GET /api/post/{id} - Get post details
- POST /api/post/{id}/upvote - Upvote post
- POST /api/post/{id}/downvote - Downvote post
- POST /api/post/{id}/comment - Comment on post

### Comments 
- POST /api/comment/{id}/reply - Reply to comment (hierarchical)
- POST /api/comment/{id}/upvote - Upvote comment
- POST /api/comment/{id}/downvote - Downvote comment

### Feed & Messages 
- GET /api/feed/{username} - Get personalized feed
- GET /api/messages/{username} - Get all messages
- POST /api/messages/send - Send direct message
- POST /api/messages/{id}/reply - Reply to message

### Statistics 
- GET /api/stats - Get complete server statistics



## Architecture

```
┌─────────────────┐
│  Web Browser    │
│  curl / CLI     │
└────────┬────────┘
         │ HTTP/JSON
         ▼
┌─────────────────┐
│   REST API      │
│  (Mist Server)  │
│   Port 8000     │
└────────┬────────┘
         │ Actor Messages
         ▼
┌─────────────────┐
│ Reddit Engine   │
│  (OTP Actors)   │
│  • Users        │
│  • Subreddits   │
│  • Posts        │
│  • Comments     │
│  • Messages     │
│  • Karma        │
└─────────────────┘
```

---

##  Project Structure

```
project4_part2/
├── src/
│   ├── reddit/
│   │   ├── engine.gleam       (1,066 lines) - Core actor engine
│   │   ├── client.gleam       (498 lines)   - Client actors
│   │   ├── models.gleam       (351 lines)   - Data models
│   │   └── simulator.gleam    (190 lines)   - Simulation
│   │
│   ├── reddit_http_api.gleam  (450 lines)   - REST API (18 endpoints)
│   ├── reddit_client_cli.gleam (80 lines)   - CLI demo client
│   ├── reddit_simulation.gleam (699 lines)  - Part 1 simulation
│   └── test_*.gleam           (12 files)    - Test suite
│
├── API_TESTING_GUIDE.md       - Complete API documentation
├── README.md                  - This file
└── gleam.toml                 - Dependencies
```



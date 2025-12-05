# Reddit Clone - Complete REST API Implementation

**Team:** Venkatesh Jammalamadaka (64025294),   Akash Challa (51281562)
**Course:** COP5615 - Distributed Operating System Principles  

---



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


=========================================================
==================   FULL WORKFLOW EXAMPLES   ==================
=========================================================

---------------- USER REGISTRATION ----------------

# Register Bob
curl -X POST http://localhost:8000/api/register \
  -H "Content-Type: application/json" \
  -d '{"username": "bob", "name": "Bob Smith", "password": "secret123"}'

# Register Alice
curl -X POST http://localhost:8000/api/register \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "name": "Alice Johnson", "password": "password456"}'


---------------- SUBREDDIT CREATION + POSTING ----------------

# Bob creates subreddit
curl -X POST http://localhost:8000/api/subreddit \
  -H "Content-Type: application/json" \
  -d '{"name": "dummy_subreddit", "username": "bob"}'

# Bob creates a post
curl -X POST http://localhost:8000/api/post \
  -H "Content-Type: application/json" \
  -d '{"username": "bob", "subreddit": "dummy_subreddit", "title": "Welcome Post", "content": "This is the first post in my subreddit!"}'

# Bob upvotes his own post (post ID = 1)
curl -X POST http://localhost:8000/api/post/1/upvote \
  -H "Content-Type: application/json" \
  -d '{"username": "bob"}'


---------------- ALICE JOINS & FEED ----------------

# Alice joins subreddit
curl -X POST http://localhost:8000/api/subreddit/dummy_subreddit/join \
  -H "Content-Type: application/json" \
  -d '{"username": "alice"}'

# Alice feed (should show Bob's post)
curl http://localhost:8000/api/feed/alice


---------------- COMMENTING + UPVOTES ----------------

# Alice comments on Bob's post
curl -X POST http://localhost:8000/api/post/1/comment -H "Content-Type: application/json" -d '{"username": "alice", "content": "Great first post Bob!"}'

# Alice upvotes Bob's post
curl -X POST http://localhost:8000/api/post/1/upvote \
  -H "Content-Type: application/json" \
  -d '{"username": "alice"}'

# Get Bob's user info (karma should be 2)
curl http://localhost:8000/api/user/bob

# Bob replies to Alice
curl -X POST http://localhost:8000/api/comment/1/reply -H "Content-Type: application/json" -d '{"username": "bob", "content": "Thanks Alice!", "post_id": 1}'

# Alice replies back
curl -X POST http://localhost:8000/api/comment/2/reply -H "Content-Type: application/json" -d '{"username": "alice", "content": "Looking forward to more posts!" , "post_id": 1}'


# View hierarchical comments
curl http://localhost:8000/api/post/1/comments


---------------- DIRECT MESSAGING ----------------

# Alice → Bob
curl -X POST http://localhost:8000/api/messages/send \
  -H "Content-Type: application/json" \
  -d '{"from": "alice", "to": "bob", "content": "Hey Bob, love your subreddit!"}'

# Bob checks messages
curl http://localhost:8000/api/messages/bob

# Bob replies
curl -X POST http://localhost:8000/api/messages/1/reply \
  -H "Content-Type: application/json" \
  -d '{"from": "bob", "to": "alice", "content": "Thanks Alice! Glad you like it."}'

# Alice checks messages
curl http://localhost:8000/api/messages/alice


---------------- SUBREDDIT LEAVE + ERROR CASE ----------------

# Alice leaves subreddit
curl -X POST http://localhost:8000/api/subreddit/dummy_subreddit/leave \
  -H "Content-Type: application/json" \
  -d '{"username": "alice"}'

# Alice attempts to post again → SHOULD ERROR
curl -X POST http://localhost:8000/api/post \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "subreddit": "dummy_subreddit", "title": "My Response", "content": "Thanks for creating this subreddit!"}'


---------------- EXTRA OPERATIONS ----------------

# Get specific post details
curl http://localhost:8000/api/post/1

# Get user info
curl http://localhost:8000/api/user/bob
curl http://localhost:8000/api/user/alice

# Downvote a post
curl -X POST http://localhost:8000/api/post/1/downvote \
  -H "Content-Type: application/json" \
  -d '{"username": "alice"}'

# System stats
curl http://localhost:8000/api/stats

# Health check
curl http://localhost:8000/health


---------------- FINAL COMMENT THREAD EXAMPLE ----------------

# Alice comments again
curl -X POST http://localhost:8000/api/post/1/comment \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "content": "Great post Bob!"}'

# Bob replies
curl -X POST http://localhost:8000/api/comment/1/reply \
  -H "Content-Type: application/json" \
  -d '{"username": "bob", "content": "Thanks Alice!", "post_id": 1}'

# View comments
curl http://localhost:8000/api/post/1/comments


---

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



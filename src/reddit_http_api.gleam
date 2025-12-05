// Simple REST API - COMPLETE VERSION with all features
import gleam/bit_array
import gleam/bytes_builder
import gleam/dynamic
import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response, Response}
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import mist
import reddit/engine
import reddit/models

pub fn main() {
  io.println("Reddit REST API Server - COMPLETE")
  let assert Ok(engine) = engine.start_engine()
  io.println("✓ Engine started")

  let handler = fn(req: Request(mist.Connection)) -> Response(mist.ResponseData) {
    let body_result = mist.read_body(req, 1_000_000)
    let req_with_body = case body_result {
      Ok(r) -> r
      Error(_) -> request.set_body(req, <<>>)
    }
    route(req_with_body, engine)
  }

  let assert Ok(_) = mist.new(handler) |> mist.port(8000) |> mist.start_http
  io.println("✓ Server on http://localhost:8000")
  io.println("\n Available Endpoints:")
  io.println("  GET  /health")
  io.println("  POST /api/register (username, name, password)")
  io.println("  GET  /api/user/{username}")
  io.println("  POST /api/subreddit")
  io.println("  POST /api/subreddit/{name}/join")
  io.println("  POST /api/post (title, content)")
  io.println("  GET  /api/post/{id}")
  io.println("  POST /api/post/{id}/upvote")
  io.println("  POST /api/post/{id}/downvote")
  io.println("  POST /api/post/{id}/comment")
  io.println("  POST /api/comment/{id}/reply")
  io.println("  POST /api/comment/{id}/upvote")
  io.println("  POST /api/comment/{id}/downvote")
  io.println("  GET  /api/feed/{username}")
  io.println("  GET  /api/messages/{username}")
  io.println("  POST /api/messages/send")
  io.println("  POST /api/messages/{id}/reply")
  io.println("  GET  /api/stats")
  io.println("")
  process.sleep_forever()
}

fn route(
  req: Request(BitArray),
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  let path = request.path_segments(req)
  case path, req.method {
    ["health"], Get -> ok([#("status", json.string("ok"))])

    // Users
    ["api", "register"], Post -> register(req.body, engine)
    ["api", "user", user], Get -> get_user(user, engine)

    // Subreddits
    ["api", "subreddit"], Post -> create_sub(req.body, engine)
    ["api", "subreddit", name, "join"], Post -> join_sub(req.body, name, engine)
    ["api", "subreddit", name, "leave"], Post ->
      leave_sub(req.body, name, engine)

    // Posts
    ["api", "post"], Post -> create_post(req.body, engine)
    ["api", "post", id], Get -> get_post_by_id(id, engine)
    ["api", "post", id, "upvote"], Post -> upvote_post(req.body, id, engine)
    ["api", "post", id, "downvote"], Post -> downvote_post(req.body, id, engine)
    ["api", "post", id, "comment"], Post ->
      comment_on_post(req.body, id, engine)
    ["api", "post", id, "comments"], Get -> get_post_comments(id, engine)

    // Comments
    ["api", "comment", id, "reply"], Post ->
      reply_to_comment(req.body, id, engine)
    ["api", "comment", id, "upvote"], Post ->
      upvote_comment(req.body, id, engine)
    ["api", "comment", id, "downvote"], Post ->
      downvote_comment(req.body, id, engine)

    // Feed
    ["api", "feed", user], Get -> feed(user, engine)

    // Messages
    ["api", "messages", user], Get -> get_messages(user, engine)
    ["api", "messages", "send"], Post -> send_message(req.body, engine)
    ["api", "messages", id, "reply"], Post ->
      reply_to_message(req.body, id, engine)

    // Stats
    ["api", "stats"], Get -> stats(engine)

    _, _ -> err("Not found", 404)
  }
}

fn ok(fields: List(#(String, json.Json))) -> Response(mist.ResponseData) {
  Response(
    200,
    [#("content-type", "application/json")],
    mist.Bytes(
      json.object(fields) |> json.to_string |> bytes_builder.from_string,
    ),
  )
}

fn err(msg: String, code: Int) -> Response(mist.ResponseData) {
  Response(
    code,
    [#("content-type", "application/json")],
    mist.Bytes(
      json.object([#("error", json.string(msg))])
      |> json.to_string
      |> bytes_builder.from_string,
    ),
  )
}

fn get_field(body: BitArray, field: String) -> Result(String, Nil) {
  body
  |> bit_array.to_string
  |> result.replace_error(Nil)
  |> result.then(fn(s) {
    json.decode(s, dynamic.field(field, dynamic.string))
    |> result.replace_error(Nil)
  })
}

fn get_int_field(body: BitArray, field: String) -> Result(Int, Nil) {
  body
  |> bit_array.to_string
  |> result.replace_error(Nil)
  |> result.then(fn(s) {
    json.decode(s, dynamic.field(field, dynamic.int))
    |> result.replace_error(Nil)
  })
}

// Enhanced user registration with name and password
fn register(
  body: BitArray,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  case
    get_field(body, "username"),
    get_field(body, "name"),
    get_field(body, "password")
  {
    Ok(user), Ok(name), Ok(pass) -> {
      // Validate password length
      case bit_array.byte_size(<<pass:utf8>>) >= 6 {
        True -> {
          let reply = process.new_subject()
          // Store username only (engine limitation), but validate all fields
          process.send(engine, models.RegisterUser(user, reply))
          case process.receive(reply, 1000) {
            Ok(Ok(_)) ->
              ok([
                #("message", json.string("User registered")),
                #("username", json.string(user)),
                #("name", json.string(name)),
              ])
            Ok(Error(e)) -> err(e, 400)
            Error(_) -> err("Timeout", 408)
          }
        }
        False -> err("Password must be at least 6 characters", 400)
      }
    }
    _, _, _ -> err("Missing required fields: username, name, password", 400)
  }
}

fn get_user(
  user: String,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  let reply = process.new_subject()
  process.send(engine, models.GetUser(user, reply))
  case process.receive(reply, 1000) {
    Ok(Ok(data)) ->
      ok([
        #("username", json.string(data.username)),
        #("karma", json.int(data.karma_points)),
        #("connected", json.bool(data.is_connected)),
        #("subreddits", json.array(data.joint_subreddits, json.string)),
      ])
    Ok(Error(e)) -> err(e, 404)
    Error(_) -> err("Timeout", 408)
  }
}

// Enhanced post creation with title and content
fn create_post(
  body: BitArray,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  case
    get_field(body, "username"),
    get_field(body, "subreddit"),
    get_field(body, "title"),
    get_field(body, "content")
  {
    Ok(user), Ok(sub), Ok(title), Ok(content) -> {
      // Combine title and content for storage
      let full_content = title <> " | " <> content
      let reply = process.new_subject()
      process.send(
        engine,
        models.CreatePost(user, sub, full_content, False, reply),
      )
      case process.receive(reply, 1000) {
        Ok(Ok(post)) ->
          ok([
            #("message", json.string("Post created")),
            #("id", json.int(post.id)),
            #("title", json.string(title)),
          ])
        Ok(Error(e)) -> err(e, 400)
        Error(_) -> err("Timeout", 408)
      }
    }
    _, _, _, _ ->
      err("Missing fields: username, subreddit, title, content", 400)
  }
}

fn get_post_by_id(
  id_str: String,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  case int.parse(id_str) {
    Ok(id) -> {
      let reply = process.new_subject()
      process.send(engine, models.GetPost(id, reply))
      case process.receive(reply, 1000) {
        Ok(Ok(post)) ->
          ok([
            #("id", json.int(post.id)),
            #("username", json.string(post.username)),
            #("content", json.string(post.content)),
            #("upvotes", json.int(post.upvotes)),
            #("downvotes", json.int(post.downvotes)),
            #("comment_count", json.int(list.length(post.comments))),
          ])
        Ok(Error(e)) -> err(e, 404)
        Error(_) -> err("Timeout", 408)
      }
    }
    Error(_) -> err("Invalid ID", 400)
  }
}

fn upvote_post(
  body: BitArray,
  id_str: String,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  case get_field(body, "username"), int.parse(id_str) {
    Ok(user), Ok(id) -> {
      let reply = process.new_subject()
      process.send(engine, models.UpVotePost(user, id, reply))
      case process.receive(reply, 1000) {
        Ok(Ok(_)) -> ok([#("message", json.string("Post upvoted"))])
        Ok(Error(e)) -> err(e, 400)
        Error(_) -> err("Timeout", 408)
      }
    }
    _, _ -> err("Invalid request", 400)
  }
}

fn downvote_post(
  body: BitArray,
  id_str: String,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  case get_field(body, "username"), int.parse(id_str) {
    Ok(user), Ok(id) -> {
      let reply = process.new_subject()
      process.send(engine, models.DownVotePost(user, id, reply))
      case process.receive(reply, 1000) {
        Ok(Ok(_)) -> ok([#("message", json.string("Post downvoted"))])
        Ok(Error(e)) -> err(e, 400)
        Error(_) -> err("Timeout", 408)
      }
    }
    _, _ -> err("Invalid request", 400)
  }
}

fn comment_on_post(
  body: BitArray,
  id_str: String,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  case
    get_field(body, "username"),
    get_field(body, "content"),
    int.parse(id_str)
  {
    Ok(user), Ok(content), Ok(post_id) -> {
      let reply = process.new_subject()
      process.send(engine, models.CreateComment(user, post_id, content, reply))
      case process.receive(reply, 1000) {
        Ok(Ok(comment)) ->
          ok([
            #("message", json.string("Comment added")),
            #("comment_id", json.int(comment.id)),
          ])
        Ok(Error(e)) -> err(e, 400)
        Error(_) -> err("Timeout", 408)
      }
    }
    _, _, _ -> err("Missing fields: username, content", 400)
  }
}

fn get_post_comments(
  id_str: String,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  case int.parse(id_str) {
    Ok(id) -> {
      let reply = process.new_subject()
      process.send(engine, models.GetComments(id, reply))
      case process.receive(reply, 1000) {
        Ok(comments) ->
          ok([
            #(
              "comments",
              json.array(comments, fn(c) { comment_to_hierarchical_json(c) }),
            ),
          ])
        Error(_) -> err("Timeout", 408)
      }
    }
    Error(_) -> err("Invalid ID", 400)
  }
}

fn comment_to_hierarchical_json(comment: models.Comment) -> json.Json {
  json.object([
    #("id", json.int(comment.id)),
    #("username", json.string(comment.username)),
    #("content", json.string(comment.content)),
    #("upvotes", json.int(comment.upvotes)),
    #("downvotes", json.int(comment.downvotes)),
    #("score", json.int(comment.upvotes - comment.downvotes)),
    #("reply_count", json.int(list.length(comment.replies))),
    #("replies", json.array(comment.replies, comment_to_hierarchical_json)),
  ])
}

fn reply_to_comment(
  body: BitArray,
  id_str: String,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  case
    get_field(body, "username"),
    get_field(body, "content"),
    get_int_field(body, "post_id"),
    int.parse(id_str)
  {
    Ok(user), Ok(content), Ok(post_id), Ok(comment_id) -> {
      let reply = process.new_subject()
      process.send(
        engine,
        models.ReplyToComment(user, post_id, comment_id, content, reply),
      )
      case process.receive(reply, 1000) {
        Ok(Ok(comment)) ->
          ok([
            #("message", json.string("Reply added")),
            #("comment_id", json.int(comment.id)),
          ])
        Ok(Error(e)) -> err(e, 400)
        Error(_) -> err("Timeout", 408)
      }
    }
    _, _, _, _ -> err("Missing fields: username, content, post_id", 400)
  }
}

fn upvote_comment(
  body: BitArray,
  id_str: String,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  case get_field(body, "username"), int.parse(id_str) {
    Ok(user), Ok(id) -> {
      let reply = process.new_subject()
      process.send(engine, models.UpVoteComment(user, id, reply))
      case process.receive(reply, 1000) {
        Ok(Ok(_)) -> ok([#("message", json.string("Comment upvoted"))])
        Ok(Error(e)) -> err(e, 400)
        Error(_) -> err("Timeout", 408)
      }
    }
    _, _ -> err("Invalid request", 400)
  }
}

fn downvote_comment(
  body: BitArray,
  id_str: String,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  case get_field(body, "username"), int.parse(id_str) {
    Ok(user), Ok(id) -> {
      let reply = process.new_subject()
      process.send(engine, models.DownVoteComment(user, id, reply))
      case process.receive(reply, 1000) {
        Ok(Ok(_)) -> ok([#("message", json.string("Comment downvoted"))])
        Ok(Error(e)) -> err(e, 400)
        Error(_) -> err("Timeout", 408)
      }
    }
    _, _ -> err("Invalid request", 400)
  }
}

fn feed(
  user: String,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  let reply = process.new_subject()
  process.send(engine, models.GetFeed(user, 20, reply))
  case process.receive(reply, 1000) {
    Ok(posts) ->
      ok([
        #(
          "posts",
          json.array(posts, fn(p) {
            json.object([
              #("id", json.int(p.id)),
              #("content", json.string(p.content)),
              #("upvotes", json.int(p.upvotes)),
              #("downvotes", json.int(p.downvotes)),
            ])
          }),
        ),
      ])
    Error(_) -> err("Timeout", 408)
  }
}

fn create_sub(
  body: BitArray,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  case get_field(body, "name"), get_field(body, "username") {
    Ok(name), Ok(user) -> {
      let reply = process.new_subject()
      process.send(engine, models.CreateSubReddit(name, user, reply))
      case process.receive(reply, 1000) {
        Ok(Ok(_)) ->
          ok([
            #("message", json.string("Subreddit created")),
            #("name", json.string(name)),
          ])
        Ok(Error(e)) -> err(e, 400)
        Error(_) -> err("Timeout", 408)
      }
    }
    _, _ -> err("Missing fields", 400)
  }
}

fn join_sub(
  body: BitArray,
  name: String,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  case get_field(body, "username") {
    Ok(user) -> {
      let reply = process.new_subject()
      process.send(engine, models.UserJoinSubReddit(user, name, reply))
      case process.receive(reply, 1000) {
        Ok(Ok(_)) -> ok([#("message", json.string("Joined subreddit"))])
        Ok(Error(e)) -> err(e, 400)
        Error(_) -> err("Timeout", 408)
      }
    }
    Error(_) -> err("Missing username", 400)
  }
}

fn leave_sub(
  body: BitArray,
  name: String,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  case get_field(body, "username") {
    Ok(user) -> {
      let reply = process.new_subject()
      process.send(engine, models.UserLeaveSubReddit(user, name, reply))
      case process.receive(reply, 1000) {
        Ok(Ok(_)) -> ok([#("message", json.string("Left subreddit"))])
        Ok(Error(e)) -> err(e, 400)
        Error(_) -> err("Timeout", 408)
      }
    }
    Error(_) -> err("Missing username", 400)
  }
}

fn get_messages(
  user: String,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  let reply = process.new_subject()
  process.send(engine, models.GetDirectMessages(user, reply))
  case process.receive(reply, 1000) {
    Ok(messages) ->
      ok([
        #(
          "messages",
          json.array(messages, fn(m) {
            json.object([
              #("id", json.int(m.id)),
              #("from", json.string(m.username)),
              #("content", json.string(m.content)),
              #("read", json.bool(m.read)),
              #("reply_count", json.int(list.length(m.replies))),
            ])
          }),
        ),
      ])
    Error(_) -> err("Timeout", 408)
  }
}

fn send_message(
  body: BitArray,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  case
    get_field(body, "from"),
    get_field(body, "to"),
    get_field(body, "content")
  {
    Ok(from), Ok(to), Ok(content) -> {
      let reply = process.new_subject()
      process.send(engine, models.SendDMToUser(from, to, content, reply))
      case process.receive(reply, 1000) {
        Ok(Ok(dm)) ->
          ok([
            #("message", json.string("Message sent")),
            #("id", json.int(dm.id)),
          ])
        Ok(Error(e)) -> err(e, 400)
        Error(_) -> err("Timeout", 408)
      }
    }
    _, _, _ -> err("Missing fields: from, to, content", 400)
  }
}

fn reply_to_message(
  body: BitArray,
  id_str: String,
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  case
    get_field(body, "from"),
    get_field(body, "to"),
    get_field(body, "content"),
    int.parse(id_str)
  {
    Ok(from), Ok(to), Ok(content), Ok(dm_id) -> {
      let reply = process.new_subject()
      process.send(engine, models.ReplyToDM(from, to, dm_id, content, reply))
      case process.receive(reply, 1000) {
        Ok(Ok(_)) -> ok([#("message", json.string("Reply sent"))])
        Ok(Error(e)) -> err(e, 400)
        Error(_) -> err("Timeout", 408)
      }
    }
    _, _, _, _ -> err("Missing fields: from, to, content", 400)
  }
}

fn stats(
  engine: process.Subject(models.EngineMessage),
) -> Response(mist.ResponseData) {
  let reply = process.new_subject()
  process.send(engine, models.GetStats(reply))
  case process.receive(reply, 1000) {
    Ok(s) ->
      ok([
        #("total_users", json.int(s.total_users)),
        #("total_posts", json.int(s.total_posts)),
        #("total_subreddits", json.int(s.total_subreddits)),
        #("total_comments", json.int(s.total_comments)),
        #("total_messages", json.int(s.total_messages)),
        #("upvote_count", json.int(s.upvote_count)),
        #("downvote_count", json.int(s.downvote_count)),
      ])
    Error(_) -> err("Timeout", 408)
  }
}

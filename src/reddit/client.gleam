// src/reddit/client.gleam
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

import reddit/models.{
  type ClientMessage, type Comment, type DM, type EngineMessage, type Post,
}

/// The client state
pub type ClientState {
  ClientState(
    id: String,
    username: Option(String),
    engine: process.Subject(EngineMessage),
    is_connected: Bool,
    joint_subreddits: List(String),
    posts: List(Post),
    comments: Dict(Int, List(Comment)),
    messages: List(DM),
    activity_count: Int,
    last_activity: Int,
    karma: Int,
  )
}

/// Initialize a new client
pub fn init_client(
  id: String,
  engine: process.Subject(EngineMessage),
) -> ClientState {
  ClientState(
    id: id,
    username: None,
    engine: engine,
    is_connected: False,
    joint_subreddits: [],
    posts: [],
    comments: dict.new(),
    messages: [],
    activity_count: 0,
    last_activity: 1_000_000,
    karma: 0,
  )
}

/// Handle client messages
pub fn handle_client_message(
  message: ClientMessage,
  state: ClientState,
) -> actor.Next(ClientMessage, ClientState) {
  let updated_state =
    ClientState(..state, activity_count: state.activity_count + 1)

  case message {
    models.Connect -> {
      case state.is_connected {
        True -> actor.continue(state)
        False -> {
          let updated_state = ClientState(..state, is_connected: True)

          // When connecting, register the user if not already registered
          case state.username {
            Some(username) -> {
              // Update connection status in engine
              process.send(
                state.engine,
                models.UpdateConnectionStatus(username, True),
              )
              actor.continue(updated_state)
            }
            None -> {
              // Register user with engine
              let username = "user_" <> state.id
              let reply = process.new_subject()
              process.send(state.engine, models.RegisterUser(username, reply))

              // Wait for response and update state
              case process.receive(reply, 1000) {
                Ok(Ok(_)) -> {
                  let final_state =
                    ClientState(..updated_state, username: Some(username))
                  io.println(
                    "🔌 Client " <> state.id <> " connected as " <> username,
                  )
                  actor.continue(final_state)
                }
                _ -> {
                  io.println(" Client " <> state.id <> " failed to register")
                  actor.continue(updated_state)
                }
              }
            }
          }
        }
      }
    }

    models.Disconnect -> {
      let new_state = ClientState(..updated_state, is_connected: False)
      case state.username {
        Some(username) -> {
          process.send(
            state.engine,
            models.UpdateConnectionStatus(username, False),
          )
          io.println(
            " Client " <> state.id <> " (" <> username <> ") disconnected",
          )
        }
        None -> Nil
      }
      actor.continue(new_state)
    }

    models.PerformRandomAction -> {
      case state.username {
        None -> actor.continue(updated_state)
        Some(username) -> {
          // Generate simple random action based on activity count
          let action_num = state.activity_count % 6

          case action_num {
            0 -> perform_create_subreddit(username, state)
            1 -> perform_join_random_subreddit(username, state)
            2 -> perform_create_post(username, state)
            3 -> perform_create_comment(username, state)
            4 -> perform_vote_random(username, state)
            _ -> perform_get_feed(username, state)
          }

          actor.continue(updated_state)
        }
      }
    }

    models.CreateSubreddit(name) -> {
      case state.username {
        Some(username) -> {
          let reply = process.new_subject()
          process.send(
            state.engine,
            models.CreateSubReddit(name, username, reply),
          )
          case process.receive(reply, 1000) {
            Ok(Ok(_)) ->
              io.println(" " <> username <> " created subreddit: " <> name)
            Ok(Error(msg)) ->
              io.println(
                " " <> username <> " failed to create subreddit: " <> msg,
              )
            Error(_) ->
              io.println(" " <> username <> " subreddit creation timeout")
          }
        }
        None -> Nil
      }
      actor.continue(updated_state)
    }

    models.JoinRandomSubreddit -> {
      case state.username {
        Some(username) -> {
          // Try to join "programming" subreddit (we'll make this more random later)
          let reply = process.new_subject()
          process.send(
            state.engine,
            models.UserJoinSubReddit(username, "programming", reply),
          )
          case process.receive(reply, 1000) {
            Ok(Ok(_)) -> io.println(" " <> username <> " joined programming")
            Ok(Error(_)) -> Nil
            // Subreddit might not exist or user already joined
            Error(_) -> Nil
          }
        }
        None -> Nil
      }
      actor.continue(updated_state)
    }

    models.ClientCreatePost(subreddit_name, content, is_repost) -> {
      case state.username {
        Some(username) -> {
          let reply = process.new_subject()
          process.send(
            state.engine,
            models.CreatePost(
              username,
              subreddit_name,
              content,
              is_repost,
              reply,
            ),
          )
          case process.receive(reply, 1000) {
            Ok(Ok(_post)) ->
              io.println(" " <> username <> " posted: " <> content)
            Ok(Error(msg)) ->
              io.println(" " <> username <> " post failed: " <> msg)
            Error(_) -> io.println(" " <> username <> " post timeout")
          }
        }
        None -> Nil
      }
      actor.continue(updated_state)
    }

    models.GetClientStats(reply_to) -> {
      let stats =
        models.ClientStats(
          client_id: state.id,
          username: state.username,
          connected: state.is_connected,
          activity_count: state.activity_count,
          karma: state.karma,
          subreddit_count: list.length(state.joint_subreddits),
          post_count: list.length(state.posts),
          comment_count: 0,
          message_count: list.length(state.messages),
        )
      process.send(reply_to, stats)
      actor.continue(updated_state)
    }

    models.UpvotePost(post_id) -> {
      case state.username {
        Some(username) -> {
          let reply = process.new_subject()
          process.send(
            state.engine,
            models.UpVotePost(username, post_id, reply),
          )
          case process.receive(reply, 500) {
            Ok(_) -> Nil
            Error(_) -> Nil
          }
        }
        None -> Nil
      }
      actor.continue(updated_state)
    }

    models.DownvotePost(post_id) -> {
      case state.username {
        Some(username) -> {
          let reply = process.new_subject()
          process.send(
            state.engine,
            models.DownVotePost(username, post_id, reply),
          )
          case process.receive(reply, 500) {
            Ok(_) -> Nil
            Error(_) -> Nil
          }
        }
        None -> Nil
      }
      actor.continue(updated_state)
    }

    models.FetchFeed(limit) -> {
      case state.username {
        Some(username) -> {
          let reply = process.new_subject()
          process.send(state.engine, models.GetFeed(username, limit, reply))
          case process.receive(reply, 500) {
            Ok(_) -> Nil
            Error(_) -> Nil
          }
        }
        None -> Nil
      }
      actor.continue(updated_state)
    }

    models.SendDirectMessage(to_username, content) -> {
      case state.username {
        Some(from_username) -> {
          let reply = process.new_subject()
          process.send(
            state.engine,
            models.SendDMToUser(from_username, to_username, content, reply),
          )
          case process.receive(reply, 1000) {
            Ok(Ok(_)) ->
              io.println(" " <> from_username <> " sent DM to " <> to_username)
            Ok(Error(msg)) -> io.println(" DM failed: " <> msg)
            Error(_) -> io.println(" DM timeout")
          }
        }
        None -> Nil
      }
      actor.continue(updated_state)
    }

    models.FetchMessages -> {
      case state.username {
        Some(username) -> {
          let reply = process.new_subject()
          process.send(state.engine, models.GetDirectMessages(username, reply))
          case process.receive(reply, 1000) {
            Ok(messages) -> {
              io.println(
                " "
                <> username
                <> " has "
                <> int.to_string(list.length(messages))
                <> " messages",
              )
            }
            Error(_) -> io.println(" Fetch messages timeout")
          }
        }
        None -> Nil
      }
      actor.continue(updated_state)
    }

    models.ReplyToDirectMessage(message_id, content) -> {
      case state.username {
        Some(username) -> {
          // Note: We need to know who to reply to - this is simplified
          let reply = process.new_subject()
          process.send(
            state.engine,
            models.ReplyToDM(username, "unknown", message_id, content, reply),
          )
          case process.receive(reply, 1000) {
            Ok(Ok(_)) ->
              io.println(
                " "
                <> username
                <> " replied to message "
                <> int.to_string(message_id),
              )
            Ok(Error(msg)) -> io.println(" Reply failed: " <> msg)
            Error(_) -> io.println(" Reply timeout")
          }
        }
        None -> Nil
      }
      actor.continue(updated_state)
    }

    models.LeaveSubreddit(subreddit_name) -> {
      case state.username {
        Some(username) -> {
          let reply = process.new_subject()
          process.send(
            state.engine,
            models.UserLeaveSubReddit(username, subreddit_name, reply),
          )
          case process.receive(reply, 1000) {
            Ok(Ok(_)) ->
              io.println(" " <> username <> " left " <> subreddit_name)
            Ok(Error(msg)) -> io.println(" Leave failed: " <> msg)
            Error(_) -> io.println(" Leave timeout")
          }
        }
        None -> Nil
      }
      actor.continue(updated_state)
    }

    models.CommentOnPost(post_id, content) -> {
      case state.username {
        Some(username) -> {
          let reply = process.new_subject()
          process.send(
            state.engine,
            models.CreateComment(username, post_id, content, reply),
          )
          case process.receive(reply, 1000) {
            Ok(Ok(_)) ->
              io.println(
                " "
                <> username
                <> " commented on post "
                <> int.to_string(post_id),
              )
            Ok(Error(msg)) ->
              io.println(" " <> username <> " comment failed: " <> msg)
            Error(_) -> io.println(" " <> username <> " comment timeout")
          }
        }
        None -> Nil
      }
      actor.continue(updated_state)
    }

    models.ClientReplyToComment(post_id, comment_id, content) -> {
      case state.username {
        Some(username) -> {
          let reply = process.new_subject()
          process.send(
            state.engine,
            models.ReplyToComment(username, post_id, comment_id, content, reply),
          )
          case process.receive(reply, 1000) {
            Ok(Ok(_)) ->
              io.println(
                "  "
                <> username
                <> " replied to comment "
                <> int.to_string(comment_id),
              )
            Ok(Error(msg)) ->
              io.println(" " <> username <> " reply failed: " <> msg)
            Error(_) -> io.println(" " <> username <> " reply timeout")
          }
        }
        None -> Nil
      }
      actor.continue(updated_state)
    }

    _ -> {
      // Handle all other messages by just continuing
      actor.continue(updated_state)
    }
  }
}

// Helper functions for random actions
fn perform_create_subreddit(username: String, state: ClientState) {
  let subreddit_name = username <> "_sub"
  let reply = process.new_subject()
  process.send(
    state.engine,
    models.CreateSubReddit(subreddit_name, username, reply),
  )
  let _ = process.receive(reply, 500)
  // Don't wait long
  Nil
}

fn perform_join_random_subreddit(username: String, state: ClientState) {
  let reply = process.new_subject()
  process.send(
    state.engine,
    models.UserJoinSubReddit(username, "programming", reply),
  )
  let _ = process.receive(reply, 500)
  Nil
}

fn perform_create_post(username: String, state: ClientState) {
  let content = "Random post by " <> username
  let reply = process.new_subject()
  process.send(
    state.engine,
    models.CreatePost(username, "programming", content, False, reply),
  )
  let _ = process.receive(reply, 500)
  Nil
}

fn perform_create_comment(username: String, state: ClientState) {
  let content = "Comment by " <> username
  let reply = process.new_subject()
  process.send(state.engine, models.CreateComment(username, 1, content, reply))
  let _ = process.receive(reply, 500)
  Nil
}

fn perform_vote_random(username: String, state: ClientState) {
  let reply = process.new_subject()
  process.send(state.engine, models.UpVotePost(username, 1, reply))
  let _ = process.receive(reply, 500)
  Nil
}

fn perform_get_feed(username: String, state: ClientState) {
  let reply = process.new_subject()
  process.send(state.engine, models.GetFeed(username, 5, reply))
  let _ = process.receive(reply, 500)
  Nil
}

/// Start a client actor
pub fn start_client(
  client_id: String,
  engine: process.Subject(EngineMessage),
) -> Result(process.Subject(ClientMessage), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: fn() {
      let state = init_client(client_id, engine)
      actor.Ready(state, process.new_selector())
    },
    init_timeout: 1000,
    loop: handle_client_message,
  ))
}

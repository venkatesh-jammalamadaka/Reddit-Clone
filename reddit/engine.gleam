// src/reddit/engine.gleam
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/otp/actor
import gleam/result
import gleam/string

import reddit/models.{
  type Comment, type DM, type EngineMessage, type EngineStats, type Post,
  type SubReddit, type UserDataType, type UserStat,
}

/// The state maintained by the Reddit engine
pub type EngineState {
  EngineState(
    users: Dict(String, UserDataType),
    subreddits: Dict(String, SubReddit),
    posts: Dict(Int, Post),
    comments: Dict(Int, Comment),
    direct_messages: Dict(Int, DM),
    // Tracking indexes
    user_subreddits: Dict(String, List(String)),
    subreddit_posts: Dict(String, List(Int)),
    post_comments: Dict(Int, List(Int)),
    comment_replies: Dict(Int, List(Int)),
    user_messages: Dict(String, List(Int)),
    // Statistics
    start_time: Int,
    operation_count: Int,
    upvote_count: Int,
    downvote_count: Int,
    next_post_id: Int,
    next_comment_id: Int,
    next_dm_id: Int,
  )
}

/// Initialize a new engine with empty state
pub fn init_engine() -> EngineState {
  EngineState(
    users: dict.new(),
    subreddits: dict.new(),
    posts: dict.new(),
    comments: dict.new(),
    direct_messages: dict.new(),
    user_subreddits: dict.new(),
    subreddit_posts: dict.new(),
    post_comments: dict.new(),
    comment_replies: dict.new(),
    user_messages: dict.new(),
    operation_count: 0,
    start_time: get_timestamp(),
    upvote_count: 0,
    downvote_count: 0,
    next_post_id: 1,
    next_comment_id: 1,
    next_dm_id: 1,
  )
}

fn get_timestamp() -> Int {
  let base = 1_699_522_800
  let pid_num = case process.self() {
    _pid -> base % 999_999
  }
  base + pid_num
}

fn generate_post_id(state: EngineState) -> #(Int, EngineState) {
  let id = state.next_post_id
  #(id, EngineState(..state, next_post_id: id + 1))
}

fn generate_comment_id(state: EngineState) -> #(Int, EngineState) {
  let id = state.next_comment_id
  #(id, EngineState(..state, next_comment_id: id + 1))
}

fn generate_dm_id(state: EngineState) -> #(Int, EngineState) {
  let id = state.next_dm_id
  #(id, EngineState(..state, next_dm_id: id + 1))
}

pub fn handle_engine_message(
  message: EngineMessage,
  state: EngineState,
) -> actor.Next(EngineMessage, EngineState) {
  // Increment operation count for each message
  let state = EngineState(..state, operation_count: state.operation_count + 1)

  case message {
    // User operations
    models.RegisterUser(username, reply_to) -> {
      case dict.has_key(state.users, username) {
        True -> {
          process.send(reply_to, Error("Username already taken"))
          actor.continue(state)
        }
        False -> {
          let user =
            models.UserDataType(
              username: username,
              joint_subreddits: [],
              dm: [],
              karma_points: 0,
              is_connected: True,
            )

          let updated_users = dict.insert(state.users, username, user)
          let updated_state = EngineState(..state, users: updated_users)

          process.send(reply_to, Ok(user))
          actor.continue(updated_state)
        }
      }
    }

    models.GetUser(username, reply_to) -> {
      case dict.get(state.users, username) {
        Ok(user) -> {
          process.send(reply_to, Ok(user))
        }
        Error(_) -> {
          process.send(reply_to, Error("User not found"))
        }
      }
      actor.continue(state)
    }

    models.UpdateConnectionStatus(username, is_connected) -> {
      case dict.get(state.users, username) {
        Error(_) -> {
          actor.continue(state)
        }
        Ok(user) -> {
          let updated_user =
            models.UserDataType(..user, is_connected: is_connected)
          let updated_users = dict.insert(state.users, username, updated_user)
          let updated_state = EngineState(..state, users: updated_users)
          actor.continue(updated_state)
        }
      }
    }

    models.CreateSubReddit(name, username, reply_to) -> {
      case dict.get(state.users, username) {
        Error(_) -> {
          process.send(reply_to, Error("User not found"))
          actor.continue(state)
        }
        Ok(user) -> {
          case dict.has_key(state.subreddits, name) {
            True -> {
              process.send(reply_to, Error("Subreddit already exists"))
              actor.continue(state)
            }
            False -> {
              let subreddit = models.SubReddit(name: name, list_of_posts: [])
              let updated_subreddits =
                dict.insert(state.subreddits, name, subreddit)

              let user_subs = case dict.get(state.user_subreddits, username) {
                Ok(subs) -> [name, ..subs]
                Error(_) -> [name]
              }
              let updated_user_subs =
                dict.insert(state.user_subreddits, username, user_subs)

              let updated_user =
                models.UserDataType(..user, joint_subreddits: user_subs)
              let updated_users =
                dict.insert(state.users, username, updated_user)

              let updated_state =
                EngineState(
                  ..state,
                  subreddits: updated_subreddits,
                  user_subreddits: updated_user_subs,
                  users: updated_users,
                )

              process.send(reply_to, Ok(subreddit))
              actor.continue(updated_state)
            }
          }
        }
      }
    }

    models.ListSubReddits(reply_to) -> {
      let subreddits = dict.values(state.subreddits)
      process.send(reply_to, subreddits)
      actor.continue(state)
    }

    models.UserJoinSubReddit(username, subreddit_name, reply_to) -> {
      case dict.get(state.users, username) {
        Error(_) -> {
          process.send(reply_to, Error("User not found"))
          actor.continue(state)
        }
        Ok(user) -> {
          case dict.has_key(state.subreddits, subreddit_name) {
            False -> {
              process.send(reply_to, Error("Subreddit not found"))
              actor.continue(state)
            }
            True -> {
              case list.contains(user.joint_subreddits, subreddit_name) {
                True -> {
                  process.send(reply_to, Error("User already in subreddit"))
                  actor.continue(state)
                }
                False -> {
                  let updated_user =
                    models.UserDataType(..user, joint_subreddits: [
                      subreddit_name,
                      ..user.joint_subreddits
                    ])
                  let updated_users =
                    dict.insert(state.users, username, updated_user)

                  let user_subs = case
                    dict.get(state.user_subreddits, username)
                  {
                    Ok(subs) -> [subreddit_name, ..subs]
                    Error(_) -> [subreddit_name]
                  }
                  let updated_user_subs =
                    dict.insert(state.user_subreddits, username, user_subs)

                  let updated_state =
                    EngineState(
                      ..state,
                      users: updated_users,
                      user_subreddits: updated_user_subs,
                    )

                  io.println("✓ " <> username <> " joined " <> subreddit_name)
                  process.send(reply_to, Ok(Nil))
                  actor.continue(updated_state)
                }
              }
            }
          }
        }
      }
    }

    models.UserLeaveSubReddit(username, subreddit_name, reply_to) -> {
      case dict.get(state.users, username) {
        Error(_) -> {
          process.send(reply_to, Error("User not found"))
          actor.continue(state)
        }
        Ok(user) -> {
          case dict.has_key(state.subreddits, subreddit_name) {
            False -> {
              process.send(reply_to, Error("Subreddit not found"))
              actor.continue(state)
            }
            True -> {
              case list.contains(user.joint_subreddits, subreddit_name) {
                False -> {
                  process.send(reply_to, Error("User not in subreddit"))
                  actor.continue(state)
                }
                True -> {
                  let updated_subreddits =
                    list.filter(user.joint_subreddits, fn(sub) {
                      sub != subreddit_name
                    })

                  let updated_user =
                    models.UserDataType(
                      ..user,
                      joint_subreddits: updated_subreddits,
                    )
                  let updated_users =
                    dict.insert(state.users, username, updated_user)

                  let user_subs = case
                    dict.get(state.user_subreddits, username)
                  {
                    Ok(subs) ->
                      list.filter(subs, fn(sub) { sub != subreddit_name })
                    Error(_) -> []
                  }
                  let updated_user_subs =
                    dict.insert(state.user_subreddits, username, user_subs)

                  let updated_state =
                    EngineState(
                      ..state,
                      users: updated_users,
                      user_subreddits: updated_user_subs,
                    )

                  io.println("✓ " <> username <> " left " <> subreddit_name)
                  process.send(reply_to, Ok(Nil))
                  actor.continue(updated_state)
                }
              }
            }
          }
        }
      }
    }

    models.GetStats(reply_to) -> {
      let user_stats = dict.new()
      // Simplified for now
      let elapsed_time = get_timestamp() - state.start_time
      let ops_per_second = case elapsed_time > 0 {
        True ->
          int.to_float(state.operation_count)
          /. int.to_float(elapsed_time)
          *. 1000.0
        False -> 0.0
      }

      let stats =
        models.EngineStats(
          total_users: dict.size(state.users),
          total_posts: dict.size(state.posts),
          total_subreddits: dict.size(state.subreddits),
          total_messages: dict.size(state.direct_messages),
          total_comments: dict.size(state.comments),
          user_stats: user_stats,
          simulation_time: elapsed_time,
          total_operations: state.operation_count,
          operations_per_second: ops_per_second,
          upvote_count: state.upvote_count,
          downvote_count: state.downvote_count,
        )

      process.send(reply_to, stats)
      actor.continue(state)
    }

    models.CreatePost(username, subreddit_name, content, is_repost, reply_to) -> {
      case dict.get(state.users, username) {
        Error(_) -> {
          process.send(reply_to, Error("User not found"))
          actor.continue(state)
        }
        Ok(user) -> {
          // ← Now we have 'user' variable
          case dict.get(state.subreddits, subreddit_name) {
            Error(_) -> {
              process.send(reply_to, Error("Subreddit not found"))
              actor.continue(state)
            }
            Ok(subreddit) -> {
              // Check if user is actually a member of this subreddit
              case list.contains(user.joint_subreddits, subreddit_name) {
                False -> {
                  process.send(reply_to, Error("User not member of subreddit"))
                  actor.continue(state)
                }
                True -> {
                  let #(post_id, new_state) = generate_post_id(state)
                  let post =
                    models.Post(
                      id: post_id,
                      content: content,
                      username: username,
                      subreddit_name: subreddit_name,
                      upvotes: 0,
                      downvotes: 0,
                      comments: [],
                      created_at: get_timestamp(),
                      is_repost: is_repost,
                    )

                  // Add post to posts dict
                  let updated_posts =
                    dict.insert(new_state.posts, post_id, post)

                  // Update subreddit with new post
                  let updated_subreddit =
                    models.SubReddit(..subreddit, list_of_posts: [
                      post,
                      ..subreddit.list_of_posts
                    ])
                  let updated_subreddits =
                    dict.insert(
                      new_state.subreddits,
                      subreddit_name,
                      updated_subreddit,
                    )

                  // Update subreddit_posts index
                  let sub_posts = case
                    dict.get(new_state.subreddit_posts, subreddit_name)
                  {
                    Ok(posts) -> [post_id, ..posts]
                    Error(_) -> [post_id]
                  }
                  let updated_sub_posts =
                    dict.insert(
                      new_state.subreddit_posts,
                      subreddit_name,
                      sub_posts,
                    )

                  let final_state =
                    EngineState(
                      ..new_state,
                      posts: updated_posts,
                      subreddits: updated_subreddits,
                      subreddit_posts: updated_sub_posts,
                    )

                  io.println(
                    "✓ Post created: "
                    <> int.to_string(post_id)
                    <> " by "
                    <> username
                    <> " in "
                    <> subreddit_name,
                  )
                  process.send(reply_to, Ok(post))
                  actor.continue(final_state)
                }
              }
            }
          }
        }
      }
    }

    models.CreateComment(username, post_id, content, reply_to) -> {
      case dict.get(state.users, username) {
        Error(_) -> {
          process.send(reply_to, Error("User not found"))
          actor.continue(state)
        }
        Ok(_) -> {
          case dict.get(state.posts, post_id) {
            Error(_) -> {
              process.send(reply_to, Error("Post not found"))
              actor.continue(state)
            }
            Ok(post) -> {
              let #(comment_id, new_state) = generate_comment_id(state)
              let comment =
                models.Comment(
                  id: comment_id,
                  content: content,
                  username: username,
                  upvotes: 0,
                  downvotes: 0,
                  replies: [],
                )

              // Add comment to comments dict
              let updated_comments =
                dict.insert(new_state.comments, comment_id, comment)

              // Add comment to post
              let updated_post =
                models.Post(..post, comments: [comment, ..post.comments])
              let updated_posts =
                dict.insert(new_state.posts, post_id, updated_post)

              // Update post_comments index
              let post_comments = case
                dict.get(new_state.post_comments, post_id)
              {
                Ok(comments) -> [comment_id, ..comments]
                Error(_) -> [comment_id]
              }
              let updated_post_comments =
                dict.insert(new_state.post_comments, post_id, post_comments)

              let final_state =
                EngineState(
                  ..new_state,
                  comments: updated_comments,
                  posts: updated_posts,
                  post_comments: updated_post_comments,
                )

              io.println(
                "✓ Comment "
                <> int.to_string(comment_id)
                <> " created by "
                <> username
                <> " on post "
                <> int.to_string(post_id),
              )
              process.send(reply_to, Ok(comment))
              actor.continue(final_state)
            }
          }
        }
      }
    }

    models.ReplyToComment(username, post_id, comment_id, content, reply_to) -> {
      case dict.get(state.users, username) {
        Error(_) -> {
          process.send(reply_to, Error("User not found"))
          actor.continue(state)
        }
        Ok(_) -> {
          case dict.get(state.posts, post_id) {
            Error(_) -> {
              process.send(reply_to, Error("Post not found"))
              actor.continue(state)
            }
            Ok(post) -> {
              let #(reply_id, new_state) = generate_comment_id(state)
              let reply =
                models.Comment(
                  id: reply_id,
                  content: content,
                  username: username,
                  upvotes: 0,
                  downvotes: 0,
                  replies: [],
                )

              // Add reply to comments dict
              let updated_comments =
                dict.insert(new_state.comments, reply_id, reply)

              // Add reply to the target comment in post
              let #(updated_post_comments, found) =
                models.add_reply_to_comment(post.comments, comment_id, reply)

              case found {
                True -> {
                  let updated_post =
                    models.Post(..post, comments: updated_post_comments)
                  let updated_posts =
                    dict.insert(new_state.posts, post_id, updated_post)

                  // Update comment_replies index
                  let comment_replies = case
                    dict.get(new_state.comment_replies, comment_id)
                  {
                    Ok(replies) -> [reply_id, ..replies]
                    Error(_) -> [reply_id]
                  }
                  let updated_comment_replies =
                    dict.insert(
                      new_state.comment_replies,
                      comment_id,
                      comment_replies,
                    )

                  let final_state =
                    EngineState(
                      ..new_state,
                      comments: updated_comments,
                      posts: updated_posts,
                      comment_replies: updated_comment_replies,
                    )

                  io.println(
                    "✓ Reply "
                    <> int.to_string(reply_id)
                    <> " created by "
                    <> username
                    <> " to comment "
                    <> int.to_string(comment_id),
                  )
                  process.send(reply_to, Ok(reply))
                  actor.continue(final_state)
                }
                False -> {
                  process.send(reply_to, Error("Comment not found"))
                  actor.continue(new_state)
                }
              }
            }
          }
        }
      }
    }

    models.UpVotePost(username, post_id, reply_to) -> {
      case dict.get(state.users, username) {
        Error(_) -> {
          process.send(reply_to, Error("User not found"))
          actor.continue(state)
        }
        Ok(_) -> {
          case dict.get(state.posts, post_id) {
            Error(_) -> {
              process.send(reply_to, Error("Post not found"))
              actor.continue(state)
            }
            Ok(post) -> {
              let updated_post = models.Post(..post, upvotes: post.upvotes + 1)
              let updated_posts =
                dict.insert(state.posts, post_id, updated_post)

              // Update post author's karma
              case dict.get(state.users, post.username) {
                Ok(author) -> {
                  let updated_author =
                    models.UserDataType(
                      ..author,
                      karma_points: author.karma_points + 1,
                    )
                  let updated_users =
                    dict.insert(state.users, post.username, updated_author)

                  let updated_state =
                    EngineState(
                      ..state,
                      posts: updated_posts,
                      users: updated_users,
                      upvote_count: state.upvote_count + 1,
                    )

                  io.println(
                    "✓ "
                    <> username
                    <> " upvoted post "
                    <> int.to_string(post_id)
                    <> " (+"
                    <> post.username
                    <> " karma)",
                  )
                  process.send(reply_to, Ok(Nil))
                  actor.continue(updated_state)
                }
                Error(_) -> {
                  let updated_state =
                    EngineState(
                      ..state,
                      posts: updated_posts,
                      upvote_count: state.upvote_count + 1,
                    )
                  process.send(reply_to, Ok(Nil))
                  actor.continue(updated_state)
                }
              }
            }
          }
        }
      }
    }

    models.DownVotePost(username, post_id, reply_to) -> {
      case dict.get(state.users, username) {
        Error(_) -> {
          process.send(reply_to, Error("User not found"))
          actor.continue(state)
        }
        Ok(_) -> {
          case dict.get(state.posts, post_id) {
            Error(_) -> {
              process.send(reply_to, Error("Post not found"))
              actor.continue(state)
            }
            Ok(post) -> {
              let updated_post =
                models.Post(..post, downvotes: post.downvotes + 1)
              let updated_posts =
                dict.insert(state.posts, post_id, updated_post)

              // Update post author's karma (-1)
              case dict.get(state.users, post.username) {
                Ok(author) -> {
                  let updated_author =
                    models.UserDataType(
                      ..author,
                      karma_points: author.karma_points - 1,
                    )
                  let updated_users =
                    dict.insert(state.users, post.username, updated_author)

                  let updated_state =
                    EngineState(
                      ..state,
                      posts: updated_posts,
                      users: updated_users,
                      downvote_count: state.downvote_count + 1,
                    )

                  io.println(
                    "✓ "
                    <> username
                    <> " downvoted post "
                    <> int.to_string(post_id)
                    <> " (-1 karma to "
                    <> post.username
                    <> ")",
                  )
                  process.send(reply_to, Ok(Nil))
                  actor.continue(updated_state)
                }
                Error(_) -> {
                  let updated_state =
                    EngineState(
                      ..state,
                      posts: updated_posts,
                      downvote_count: state.downvote_count + 1,
                    )
                  process.send(reply_to, Ok(Nil))
                  actor.continue(updated_state)
                }
              }
            }
          }
        }
      }
    }
    models.GetComments(post_id, reply_to) -> {
      case dict.get(state.posts, post_id) {
        Ok(post) -> {
          io.println(
            "✓ Retrieved "
            <> int.to_string(list.length(post.comments))
            <> " comments for post "
            <> int.to_string(post_id),
          )
          process.send(reply_to, post.comments)
          actor.continue(state)
        }
        Error(_) -> {
          process.send(reply_to, [])
          actor.continue(state)
        }
      }
    }
    models.UpVoteComment(username, comment_id, reply_to) -> {
      case dict.get(state.users, username) {
        Error(_) -> {
          process.send(reply_to, Error("User not found"))
          actor.continue(state)
        }
        Ok(_) -> {
          case dict.get(state.comments, comment_id) {
            Error(_) -> {
              process.send(reply_to, Error("Comment not found"))
              actor.continue(state)
            }
            Ok(comment) -> {
              let updated_comment =
                models.Comment(..comment, upvotes: comment.upvotes + 1)
              let updated_comments =
                dict.insert(state.comments, comment_id, updated_comment)

              // Update comment author's karma (+1)
              case dict.get(state.users, comment.username) {
                Ok(author) -> {
                  let updated_author =
                    models.UserDataType(
                      ..author,
                      karma_points: author.karma_points + 1,
                    )
                  let updated_users =
                    dict.insert(state.users, comment.username, updated_author)

                  let updated_state =
                    EngineState(
                      ..state,
                      comments: updated_comments,
                      users: updated_users,
                      upvote_count: state.upvote_count + 1,
                    )

                  io.println(
                    "✓ "
                    <> username
                    <> " upvoted comment "
                    <> int.to_string(comment_id)
                    <> " (+1 karma to "
                    <> comment.username
                    <> ")",
                  )
                  process.send(reply_to, Ok(Nil))
                  actor.continue(updated_state)
                }
                Error(_) -> {
                  let updated_state =
                    EngineState(
                      ..state,
                      comments: updated_comments,
                      upvote_count: state.upvote_count + 1,
                    )
                  process.send(reply_to, Ok(Nil))
                  actor.continue(updated_state)
                }
              }
            }
          }
        }
      }
    }

    models.DownVoteComment(username, comment_id, reply_to) -> {
      case dict.get(state.users, username) {
        Error(_) -> {
          process.send(reply_to, Error("User not found"))
          actor.continue(state)
        }
        Ok(_) -> {
          case dict.get(state.comments, comment_id) {
            Error(_) -> {
              process.send(reply_to, Error("Comment not found"))
              actor.continue(state)
            }
            Ok(comment) -> {
              let updated_comment =
                models.Comment(..comment, downvotes: comment.downvotes + 1)
              let updated_comments =
                dict.insert(state.comments, comment_id, updated_comment)

              // Update comment author's karma (-1)
              case dict.get(state.users, comment.username) {
                Ok(author) -> {
                  let updated_author =
                    models.UserDataType(
                      ..author,
                      karma_points: author.karma_points - 1,
                    )
                  let updated_users =
                    dict.insert(state.users, comment.username, updated_author)

                  let updated_state =
                    EngineState(
                      ..state,
                      comments: updated_comments,
                      users: updated_users,
                      downvote_count: state.downvote_count + 1,
                    )

                  io.println(
                    "✓ "
                    <> username
                    <> " downvoted comment "
                    <> int.to_string(comment_id)
                    <> " (-1 karma to "
                    <> comment.username
                    <> ")",
                  )
                  process.send(reply_to, Ok(Nil))
                  actor.continue(updated_state)
                }
                Error(_) -> {
                  let updated_state =
                    EngineState(
                      ..state,
                      comments: updated_comments,
                      downvote_count: state.downvote_count + 1,
                    )
                  process.send(reply_to, Ok(Nil))
                  actor.continue(updated_state)
                }
              }
            }
          }
        }
      }
    }

    models.GetFeed(username, limit, reply_to) -> {
      case dict.get(state.users, username) {
        Error(_) -> {
          process.send(reply_to, [])
          actor.continue(state)
        }
        Ok(user) -> {
          // Get current posts with up-to-date vote counts from state.posts
          // Filter posts that belong to subreddits the user has joined
          let user_posts =
            dict.values(state.posts)
            |> list.filter(fn(post) {
              list.contains(user.joint_subreddits, post.subreddit_name)
            })

          // Sort posts by ID (newer posts have higher IDs) and limit
          let sorted_posts =
            list.sort(user_posts, fn(a, b) {
              case a.id > b.id {
                True -> order.Lt
                False ->
                  case a.id < b.id {
                    True -> order.Gt
                    False -> order.Eq
                  }
              }
            })

          let limited_posts = list.take(sorted_posts, limit)

          io.println(
            "✓ Feed generated for "
            <> username
            <> " with "
            <> int.to_string(list.length(limited_posts))
            <> " posts",
          )
          process.send(reply_to, limited_posts)
          actor.continue(state)
        }
      }
    }

    models.GetPost(post_id, reply_to) -> {
      case dict.get(state.posts, post_id) {
        Ok(post) -> {
          process.send(reply_to, Ok(post))
          actor.continue(state)
        }
        Error(_) -> {
          process.send(reply_to, Error("Post not found"))
          actor.continue(state)
        }
      }
    }

    models.SendDMToUser(from_username, to_username, content, reply_to) -> {
      case dict.get(state.users, from_username) {
        Error(_) -> {
          process.send(reply_to, Error("Sender not found"))
          actor.continue(state)
        }
        Ok(_) -> {
          case dict.get(state.users, to_username) {
            Error(_) -> {
              process.send(reply_to, Error("Recipient not found"))
              actor.continue(state)
            }
            Ok(recipient) -> {
              let #(dm_id, new_state) = generate_dm_id(state)
              let dm =
                models.DM(
                  id: dm_id,
                  username: from_username,
                  content: content,
                  replies: [],
                  created_at: get_timestamp(),
                  read: False,
                )

              // Store DM
              let updated_dms =
                dict.insert(new_state.direct_messages, dm_id, dm)

              // Add to recipient's message list
              let user_messages = case
                dict.get(new_state.user_messages, to_username)
              {
                Ok(messages) -> [dm_id, ..messages]
                Error(_) -> [dm_id]
              }
              let updated_user_messages =
                dict.insert(new_state.user_messages, to_username, user_messages)

              // Update recipient's user data
              let updated_recipient =
                models.UserDataType(..recipient, dm: [dm, ..recipient.dm])
              let updated_users =
                dict.insert(new_state.users, to_username, updated_recipient)

              let final_state =
                EngineState(
                  ..new_state,
                  direct_messages: updated_dms,
                  user_messages: updated_user_messages,
                  users: updated_users,
                )

              io.println(
                "✓ DM "
                <> int.to_string(dm_id)
                <> " sent from "
                <> from_username
                <> " to "
                <> to_username,
              )
              process.send(reply_to, Ok(dm))
              actor.continue(final_state)
            }
          }
        }
      }
    }

    models.GetDirectMessages(username, reply_to) -> {
      case dict.get(state.users, username) {
        Ok(user) -> {
          process.send(reply_to, user.dm)
          actor.continue(state)
        }
        Error(_) -> {
          process.send(reply_to, [])
          actor.continue(state)
        }
      }
    }

    models.ReplyToDM(from_username, to_username, message_id, content, reply_to) -> {
      case dict.get(state.direct_messages, message_id) {
        Error(_) -> {
          process.send(reply_to, Error("Message not found"))
          actor.continue(state)
        }
        Ok(original_dm) -> {
          let #(reply_id, new_state) = generate_dm_id(state)
          let reply_dm =
            models.DM(
              id: reply_id,
              username: from_username,
              content: content,
              replies: [],
              created_at: get_timestamp(),
              read: False,
            )

          // Add reply to original message
          let updated_dm =
            models.DM(..original_dm, replies: [reply_dm, ..original_dm.replies])
          let updated_dms =
            dict.insert(new_state.direct_messages, message_id, updated_dm)

          // Store the reply as a separate message too
          let updated_dms2 = dict.insert(updated_dms, reply_id, reply_dm)

          // Add to recipient's message list
          case dict.get(new_state.users, to_username) {
            Ok(recipient) -> {
              let updated_recipient =
                models.UserDataType(..recipient, dm: [reply_dm, ..recipient.dm])
              let updated_users =
                dict.insert(new_state.users, to_username, updated_recipient)

              let user_messages = case
                dict.get(new_state.user_messages, to_username)
              {
                Ok(messages) -> [reply_id, ..messages]
                Error(_) -> [reply_id]
              }
              let updated_user_messages =
                dict.insert(new_state.user_messages, to_username, user_messages)

              let final_state =
                EngineState(
                  ..new_state,
                  direct_messages: updated_dms2,
                  users: updated_users,
                  user_messages: updated_user_messages,
                )

              io.println(
                "✓ Reply "
                <> int.to_string(reply_id)
                <> " sent from "
                <> from_username
                <> " to "
                <> to_username,
              )
              process.send(reply_to, Ok(reply_dm))
              actor.continue(final_state)
            }
            Error(_) -> {
              process.send(reply_to, Error("Recipient not found"))
              actor.continue(new_state)
            }
          }
        }
      }
    }

    _ -> {
      // Handle any remaining unimplemented messages
      actor.continue(state)
    }
  }
}

/// Start the Reddit engine actor
pub fn start_engine() -> Result(
  process.Subject(EngineMessage),
  actor.StartError,
) {
  actor.start_spec(actor.Spec(
    init: fn() {
      let state = init_engine()
      actor.Ready(state, process.new_selector())
    },
    init_timeout: 1000,
    loop: handle_engine_message,
  ))
}

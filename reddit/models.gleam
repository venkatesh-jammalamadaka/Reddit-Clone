// src/reddit/models.gleam
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option}

/// User data type with connection status
pub type UserDataType {
  UserDataType(
    username: String,
    joint_subreddits: List(String),
    dm: List(DM),
    karma_points: Int,
    is_connected: Bool,
  )
}

/// Direct Message with support for replies
pub type DM {
  DM(
    id: Int,
    username: String,
    content: String,
    replies: List(DM),
    created_at: Int,
    read: Bool,
  )
}

/// SubReddit model
pub type SubReddit {
  SubReddit(name: String, list_of_posts: List(Post))
}

/// Post model
pub type Post {
  Post(
    id: Int,
    content: String,
    username: String,
    subreddit_name: String,
    upvotes: Int,
    downvotes: Int,
    comments: List(Comment),
    created_at: Int,
    is_repost: Bool,
  )
}

/// Comment model with support for hierarchical replies
pub type Comment {
  Comment(
    id: Int,
    content: String,
    username: String,
    upvotes: Int,
    downvotes: Int,
    replies: List(Comment),
  )
}

/// User statistics
pub type UserStat {
  UserStat(
    karma: Int,
    post_count: Int,
    comment_count: Int,
    upvote_count: Int,
    downvote_count: Int,
  )
}

/// Engine statistics
pub type EngineStats {
  EngineStats(
    total_users: Int,
    total_posts: Int,
    total_subreddits: Int,
    total_messages: Int,
    total_comments: Int,
    user_stats: Dict(String, UserStat),
    simulation_time: Int,
    total_operations: Int,
    operations_per_second: Float,
    upvote_count: Int,
    downvote_count: Int,
  )
}

/// Helper function to add a reply to a comment
pub fn add_reply_to_comment(
  comments: List(Comment),
  target_id: Int,
  reply: Comment,
) -> #(List(Comment), Bool) {
  add_reply_recursive(comments, target_id, reply, [])
}

// Helper function that maintains order
fn add_reply_recursive(
  comments: List(Comment),
  target_id: Int,
  reply: Comment,
  acc: List(Comment),
) -> #(List(Comment), Bool) {
  case comments {
    [] -> #(list.reverse(acc), False)
    [comment, ..rest] -> {
      case comment.id == target_id {
        True -> {
          // Found target comment, add reply
          let updated_comment =
            Comment(..comment, replies: [reply, ..comment.replies])
          let final_list =
            list.reverse(acc)
            |> list.append([updated_comment])
            |> list.append(rest)
          #(final_list, True)
        }
        False -> {
          // Try to find in nested replies
          let #(updated_replies, found) =
            add_reply_recursive(comment.replies, target_id, reply, [])
          case found {
            True -> {
              let updated_comment = Comment(..comment, replies: updated_replies)
              let final_list =
                list.reverse(acc)
                |> list.append([updated_comment])
                |> list.append(rest)
              #(final_list, True)
            }
            False -> {
              // Continue searching
              add_reply_recursive(rest, target_id, reply, [comment, ..acc])
            }
          }
        }
      }
    }
  }
}

/// Helper function to calculate karma for a user
pub fn calculate_karma(posts: List(Post), comments: List(Comment)) -> Int {
  let post_karma =
    list.fold(posts, 0, fn(acc, post) { acc + post.upvotes - post.downvotes })

  let comment_karma = calculate_comment_karma(comments)

  post_karma + comment_karma
}

/// Helper function to calculate karma from comments (including nested replies)
pub fn calculate_comment_karma(comments: List(Comment)) -> Int {
  list.fold(comments, 0, fn(acc, comment) {
    let direct_karma = comment.upvotes - comment.downvotes
    let reply_karma = calculate_comment_karma(comment.replies)

    acc + direct_karma + reply_karma
  })
}

/// Message types for the Reddit engine
pub type EngineMessage {
  // User operations
  RegisterUser(
    username: String,
    reply_to: process.Subject(Result(UserDataType, String)),
  )
  GetUser(
    username: String,
    reply_to: process.Subject(Result(UserDataType, String)),
  )
  UpdateConnectionStatus(username: String, is_connected: Bool)

  // SubReddit operations
  CreateSubReddit(
    name: String,
    username: String,
    reply_to: process.Subject(Result(SubReddit, String)),
  )
  UserJoinSubReddit(
    username: String,
    subreddit_name: String,
    reply_to: process.Subject(Result(Nil, String)),
  )
  UserLeaveSubReddit(
    username: String,
    subreddit_name: String,
    reply_to: process.Subject(Result(Nil, String)),
  )
  GetSubReddit(
    name: String,
    reply_to: process.Subject(Result(SubReddit, String)),
  )
  ListSubReddits(reply_to: process.Subject(List(SubReddit)))

  // Post operations
  CreatePost(
    username: String,
    subreddit_name: String,
    content: String,
    is_repost: Bool,
    reply_to: process.Subject(Result(Post, String)),
  )
  GetPost(post_id: Int, reply_to: process.Subject(Result(Post, String)))
  GetFeed(username: String, limit: Int, reply_to: process.Subject(List(Post)))
  UpVotePost(
    username: String,
    post_id: Int,
    reply_to: process.Subject(Result(Nil, String)),
  )
  DownVotePost(
    username: String,
    post_id: Int,
    reply_to: process.Subject(Result(Nil, String)),
  )

  // Comment operations
  CreateComment(
    username: String,
    post_id: Int,
    content: String,
    reply_to: process.Subject(Result(Comment, String)),
  )
  ReplyToComment(
    username: String,
    post_id: Int,
    comment_id: Int,
    content: String,
    reply_to: process.Subject(Result(Comment, String)),
  )
  GetComments(post_id: Int, reply_to: process.Subject(List(Comment)))
  UpVoteComment(
    username: String,
    comment_id: Int,
    reply_to: process.Subject(Result(Nil, String)),
  )
  DownVoteComment(
    username: String,
    comment_id: Int,
    reply_to: process.Subject(Result(Nil, String)),
  )

  // Direct Message operations
  SendDMToUser(
    from_username: String,
    to_username: String,
    content: String,
    reply_to: process.Subject(Result(DM, String)),
  )
  GetDirectMessages(username: String, reply_to: process.Subject(List(DM)))
  ReplyToDM(
    from_username: String,
    to_username: String,
    message_id: Int,
    content: String,
    reply_to: process.Subject(Result(DM, String)),
  )
  MarkMessageAsRead(
    message_id: Int,
    reply_to: process.Subject(Result(Nil, String)),
  )
  ReplyToAllDMs(
    username: String,
    content: String,
    reply_to: process.Subject(Result(Nil, String)),
  )

  // Simulation operations
  GetStats(reply_to: process.Subject(EngineStats))
}

/// Client message types
/// Client message types
pub type ClientMessage {
  // Connection management
  Connect
  Disconnect

  // Activity simulation
  SimulateActivity
  PerformRandomAction

  // User-specific actions - Rename these to avoid conflicts
  ClientRegisterUser(username: String)
  // Was: RegisterUser
  JoinRandomSubreddit
  LeaveSubreddit(subreddit_name: String)
  CreateSubreddit(name: String)
  ClientCreatePost(subreddit_name: String, content: String, is_repost: Bool)
  // Was: CreatePost
  CommentOnPost(post_id: Int, content: String)
  ClientReplyToComment(post_id: Int, comment_id: Int, content: String)
  // Was: ReplyToComment
  UpvotePost(post_id: Int)
  DownvotePost(post_id: Int)
  UpvoteComment(comment_id: Int)
  DownvoteComment(comment_id: Int)
  FetchFeed(limit: Int)
  FetchMessages
  SendDirectMessage(to_username: String, content: String)
  ReplyToDirectMessage(message_id: Int, content: String)
  ReplyToAllMessages(content: String)

  // Client data retrieval (for simulation stats)
  GetClientStats(reply_to: process.Subject(ClientStats))
}

/// Client statistics
pub type ClientStats {
  ClientStats(
    client_id: String,
    username: Option(String),
    connected: Bool,
    activity_count: Int,
    karma: Int,
    subreddit_count: Int,
    post_count: Int,
    comment_count: Int,
    message_count: Int,
  )
}

/// Simulator message types
pub type SimulatorMessage {
  // Setup
  StartSimulation(client_count: Int)

  // Connection simulation
  SimulateConnectionCycles

  // Stats collection
  CollectStats(reply_to: process.Subject(SimulationStats))
}

/// Simulation statistics
pub type SimulationStats {
  SimulationStats(
    client_count: Int,
    active_clients: Int,
    engine_stats: EngineStats,
    client_stats: List(ClientStats),
    runtime_ms: Int,
    posts_per_client: Float,
    comments_per_client: Float,
    average_karma: Float,
    start_time: Int,
  )
}

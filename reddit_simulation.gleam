import gleam/dict
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/string

import argv
import reddit/client
import reddit/engine
import reddit/models

@external(erlang, "os", "timestamp")
fn os_timestamp() -> #(Int, Int, Int)

fn now_ms() -> Int {
  let #(mega, sec, micro) = os_timestamp()
  let micros = mega * 1_000_000 * 1_000_000 + sec * 1_000_000 + micro
  micros / 1000
}

pub type SimulationConfig {
  SimulationConfig(
    user_count: Int,
    total_posts: Int,
    total_subreddits: Int,
    total_messages: Int,
    simulation_duration_ms: Int,
  )
}

pub type OperationsDistribution {
  OperationsDistribution(
    users_joining_subreddits: Int,
    users_leaving_subreddits: Int,
    posts_created: Int,
    reposts_created: Int,
    comments_created: Int,
    reply_comments_created: Int,
    upvotes_cast: Int,
    downvotes_cast: Int,
    direct_messages_sent: Int,
    dm_replies_sent: Int,
    feed_requests: Int,
    users_disconnecting: Int,
    users_reconnecting: Int,
  )
}

pub type SimulationResults {
  SimulationResults(
    config: SimulationConfig,
    actual_stats: models.EngineStats,
    time_taken_ms: Int,
    operations_per_second: Float,
    posts_per_user: Float,
    messages_per_user: Float,
    subreddits_per_user: Float,
  )
}

pub fn main() {
  let args = get_args()

  case args {
    [user_count_str] -> {
      case int.parse(user_count_str) {
        Ok(user_count) -> {
          case user_count {
            n if n <= 0 -> {
              io.println("❌ Error: User count must be positive")
              print_usage()
            }
            n if n > 10_000 -> {
              io.println(
                "⚠️  Warning: "
                <> int.to_string(n)
                <> " users is extremely large!",
              )
              io.println(
                "   This may take a very long time or cause system issues.",
              )
              io.println("   Recommended maximum: 5000 users")
              io.println("   Continue? This will start in 5 seconds...")
              process.sleep(5000)
              run_reddit_simulation(user_count)
            }
            _ -> run_reddit_simulation(user_count)
          }
        }
        Error(_) -> {
          io.println("❌ Error: Invalid number format")
          print_usage()
        }
      }
    }
    [] -> {
      io.println("❌ Error: No user count provided")
      print_usage()
    }
    _ -> {
      io.println("❌ Error: Too many arguments")
      print_usage()
    }
  }
}

fn get_args() -> List(String) {
  argv.load().arguments
}

fn print_usage() {
  io.println("")
  io.println("🚀 Reddit Clone - Scalable Simulation Framework")
  io.println("================================================")
  io.println("")
  io.println("Usage: gleam run -m reddit_simulation <number_of_users>")
  io.println("")
  io.println("Examples:")
  io.println("  gleam run -m reddit_simulation 50     # Small scale test")
  io.println("  gleam run -m reddit_simulation 250    # Medium scale test")
  io.println("  gleam run -m reddit_simulation 1000   # Large scale test")
  io.println("  gleam run -m reddit_simulation 3000   # Stress test")
  io.println("")
  io.println("📊 Scale Guidelines:")
  io.println("   🟢 10-99:     Small scale (high activity per user)")
  io.println("   🟡 100-499:   Medium scale (balanced load)")
  io.println("   🟠 500-1499:  Large scale (performance testing)")
  io.println("   🔴 1500-5000: Extreme scale (stress testing)")
  io.println("   💀 5000+:     Ultra scale (maximum load)")
  io.println("")
}

fn run_reddit_simulation(user_count: Int) {
  io.println(" Reddit Clone - Scalable Simulation")
  io.println("=====================================")
  io.println(" Simulating " <> int.to_string(user_count) <> " users")

  let config = calculate_simulation_config(user_count)
  let operations = calculate_operations_distribution(user_count)

  print_simulation_plan(config, operations)

  io.println("\n Starting simulation...")
  let results = run_simulation(config, operations)
  print_simulation_results(results)

  io.println("\n Simulation completed!")
  io.println(" Try different user counts to test scalability limits.")
}

fn calculate_simulation_config(user_count: Int) -> SimulationConfig {
  let #(posts_per_user, subreddit_ratio, messages_per_user, duration_ms) = case
    user_count
  {
    n if n < 100 -> #(2, 0.3, 1, 15_000)
    // Faster for small scale
    n if n < 250 -> #(1, 0.2, 1, 20_000)
    // Medium scale
    n if n < 500 -> #(1, 0.15, 0, 25_000)
    // Large scale
    n if n < 1000 -> #(0, 0.1, 0, 30_000)
    // Very large scale
    _ -> #(0, 0.05, 0, 35_000)
    // Extreme scale
  }

  let total_posts = user_count * posts_per_user
  let total_subreddits =
    int.max(10, float.round(int.to_float(user_count) *. subreddit_ratio))
  let total_messages = user_count * messages_per_user

  SimulationConfig(
    user_count: user_count,
    total_posts: total_posts,
    total_subreddits: total_subreddits,
    total_messages: total_messages,
    simulation_duration_ms: duration_ms,
  )
}

fn calculate_operations_distribution(user_count: Int) -> OperationsDistribution {
  case user_count {
    // Small scale (10-99): High activity per user
    n if n < 100 ->
      OperationsDistribution(
        users_joining_subreddits: n * 2,
        // Each user joins 2 subreddits
        users_leaving_subreddits: n / 10,
        // 10% leave a subreddit
        posts_created: n,
        // 1 post per user
        reposts_created: n / 20,
        // 5% create reposts
        comments_created: n * 2,
        // 2 comments per user
        reply_comments_created: n / 2,
        // 0.5 replies per user
        upvotes_cast: n * 3,
        // 3 upvotes per user
        downvotes_cast: n / 2,
        // 0.5 downvotes per user
        direct_messages_sent: n / 2,
        // 0.5 DMs per user
        dm_replies_sent: n / 4,
        // 25% reply to DMs
        feed_requests: n,
        // 1 feed check per user
        users_disconnecting: n / 5,
        // 20% disconnect
        users_reconnecting: n / 5,
        // Same users reconnect
      )

    // Medium scale (100-499): Balanced activity
    n if n < 500 ->
      OperationsDistribution(
        users_joining_subreddits: n,
        // Each user joins 1 subreddit
        users_leaving_subreddits: n / 20,
        // 5% leave a subreddit
        posts_created: n / 2,
        // 0.5 posts per user
        reposts_created: n / 50,
        // 2% create reposts
        comments_created: n,
        // 1 comment per user
        reply_comments_created: n / 4,
        // 0.25 replies per user
        upvotes_cast: n * 2,
        // 2 upvotes per user
        downvotes_cast: n / 4,
        // 0.25 downvotes per user
        direct_messages_sent: n / 4,
        // 0.25 DMs per user
        dm_replies_sent: n / 8,
        // 12.5% reply to DMs
        feed_requests: n,
        // 1 feed check per user
        users_disconnecting: n / 8,
        // 12.5% disconnect
        users_reconnecting: n / 8,
        // Same users reconnect
      )

    // Large scale (500+): Lower per-user activity
    _ ->
      OperationsDistribution(
        users_joining_subreddits: user_count / 2,
        // 0.5 subreddits per user
        users_leaving_subreddits: user_count / 50,
        // 2% leave a subreddit
        posts_created: user_count / 4,
        // 0.25 posts per user
        reposts_created: user_count / 100,
        // 1% create reposts
        comments_created: user_count / 2,
        // 0.5 comments per user
        reply_comments_created: user_count / 10,
        // 0.1 replies per user
        upvotes_cast: user_count,
        // 1 upvote per user
        downvotes_cast: user_count / 10,
        // 0.1 downvotes per user
        direct_messages_sent: 0,
        // No DMs for large scale
        dm_replies_sent: 0,
        // No DM replies
        feed_requests: user_count / 2,
        // 0.5 feed checks per user
        users_disconnecting: user_count / 10,
        // 10% disconnect
        users_reconnecting: user_count / 10,
        // Same users reconnect
      )
  }
}

fn print_simulation_plan(config: SimulationConfig, ops: OperationsDistribution) {
  io.println("\n📋 SIMULATION CONFIGURATION")
  io.println("============================")
  io.println("👥 Users: " <> int.to_string(config.user_count))
  io.println("📊 Scale: " <> get_scale_category(config.user_count))
  io.println(
    "⏱️  Duration: "
    <> int.to_string(config.simulation_duration_ms / 1000)
    <> " seconds",
  )

  io.println("\n Operation Distribution:")
  io.println(
    "    Join subreddits: " <> int.to_string(ops.users_joining_subreddits),
  )
  io.println(
    "    Leave subreddits: " <> int.to_string(ops.users_leaving_subreddits),
  )
  io.println("   Posts: " <> int.to_string(ops.posts_created))
  io.println("   Reposts: " <> int.to_string(ops.reposts_created))
  io.println("   Comments: " <> int.to_string(ops.comments_created))
  io.println("   Replies: " <> int.to_string(ops.reply_comments_created))
  io.println("   Upvotes: " <> int.to_string(ops.upvotes_cast))
  io.println("   Downvotes: " <> int.to_string(ops.downvotes_cast))
  io.println("   DMs: " <> int.to_string(ops.direct_messages_sent))
  io.println("   Feed requests: " <> int.to_string(ops.feed_requests))
  io.println("   Disconnections: " <> int.to_string(ops.users_disconnecting))

  let total_ops =
    ops.users_joining_subreddits
    + ops.posts_created
    + ops.comments_created
    + ops.upvotes_cast
    + ops.downvotes_cast
    + ops.feed_requests
  io.println("🎯 Estimated Operations: ~" <> int.to_string(total_ops))
}

fn get_scale_category(user_count: Int) -> String {
  case user_count {
    n if n < 100 -> "🟢 Small Scale"
    n if n < 500 -> "🟡 Medium Scale"
    n if n < 1500 -> "🟠 Large Scale"
    n if n <= 5000 -> "🔴 Extreme Scale"
    _ -> "💀 Ultra Scale"
  }
}

fn run_simulation(
  config: SimulationConfig,
  operations: OperationsDistribution,
) -> SimulationResults {
  let start_time = get_timestamp()

  // Start engine
  io.println("⚡ Starting Reddit engine...")
  let assert Ok(engine) = engine.start_engine()

  // Setup initial data + Create initial posts
  io.println("🏗️  Setting up initial data and posts...")
  setup_simulation_data_with_posts(engine, config)

  // Create clients
  io.println(
    "🤖 Creating " <> int.to_string(config.user_count) <> " client actors...",
  )
  let clients = create_simulation_clients(config.user_count, engine, [])

  // Connect clients
  io.println("🔌 Connecting clients...")
  connect_clients_in_batches(clients, config.user_count)

  // Run concurrent simulation (no sleeps needed!)
  io.println("🚀 Running concurrent simulation...")
  execute_concurrent_simulation(clients, operations)

  // Brief wait for final operations
  io.println("⏳ Finalizing operations...")
  process.sleep(2000)

  // Collect results
  io.println("📊 Collecting final statistics...")
  let final_stats = get_final_stats(engine)

  let end_time = get_timestamp()
  let time_taken = end_time - start_time

  let ops_per_second = case time_taken > 0 {
    True ->
      int.to_float(final_stats.total_operations)
      /. int.to_float(time_taken)
      *. 1000.0
    False -> 0.0
  }

  SimulationResults(
    config: config,
    actual_stats: final_stats,
    time_taken_ms: time_taken,
    operations_per_second: ops_per_second,
    posts_per_user: int.to_float(final_stats.total_posts)
      /. int.to_float(config.user_count),
    messages_per_user: int.to_float(final_stats.total_messages)
      /. int.to_float(config.user_count),
    subreddits_per_user: int.to_float(final_stats.total_subreddits)
      /. int.to_float(config.user_count),
  )
}

// FIXED: This function now calls the correct comment function
fn execute_concurrent_simulation(clients, ops: OperationsDistribution) {
  io.println("🔥 Executing all operations concurrently...")

  // Execute all operations at once - no waiting!
  execute_join_operations(clients, ops.users_joining_subreddits)
  execute_post_operations(clients, ops.posts_created, ops.reposts_created)

  io.println(
    "🐛 DEBUG: About to call comment operations with "
    <> int.to_string(ops.comments_created)
    <> " expected comments",
  )
  // Use the correct comment function that references existing posts
  execute_comment_operations_with_existing_posts(
    clients,
    ops.comments_created,
    ops.reply_comments_created,
  )

  execute_voting_operations(clients, ops.upvotes_cast, ops.downvotes_cast)

  case ops.direct_messages_sent > 0 {
    True -> execute_dm_operations_simple(clients, ops.direct_messages_sent)
    False -> Nil
  }

  execute_feed_operations(clients, ops.feed_requests)
  execute_connection_operations(
    clients,
    ops.users_disconnecting,
    ops.users_reconnecting,
  )
  execute_leave_operations(clients, ops.users_leaving_subreddits)

  io.println("⚡ All operations dispatched concurrently!")
}

fn execute_join_operations(clients, count) {
  let selected_clients = list.take(clients, count)
  list.each(selected_clients, fn(client) {
    process.send(client, models.JoinRandomSubreddit)
  })
}

fn execute_post_operations(clients, posts, reposts) {
  let post_clients = list.take(clients, posts)
  let repost_clients = list.take(clients, reposts)

  list.each(post_clients, fn(client) {
    process.send(
      client,
      models.ClientCreatePost("programming", "User post", False),
    )
  })

  list.each(repost_clients, fn(client) {
    process.send(
      client,
      models.ClientCreatePost("programming", "Repost content", True),
    )
  })
}

fn execute_comment_operations_with_existing_posts(clients, comments, replies) {
  io.println("🐛 DEBUG: Starting comment operations...")
  io.println("🐛 DEBUG: Expected comments: " <> int.to_string(comments))
  io.println("🐛 DEBUG: Expected replies: " <> int.to_string(replies))

  let comment_clients = list.take(clients, comments)
  //let reply_clients = list.take(clients, replies)

  io.println(
    "🐛 DEBUG: Comment clients count: "
    <> int.to_string(list.length(comment_clients)),
  )
  //   io.println(
  //     "🐛 DEBUG: Reply clients count: "
  //     <> int.to_string(list.length(reply_clients)),
  //   )

  // Comment on existing posts (IDs 1-5)
  list.each(comment_clients, fn(client) {
    let post_id = { list.length(comment_clients) % 5 } + 1
    io.println("🐛 DEBUG: Sending comment to post " <> int.to_string(post_id))
    process.send(client, models.CommentOnPost(post_id, "Great post!"))
  })

  // Reply to comments (assuming comment IDs start from 6)
  //   list.each(reply_clients, fn(client) {
  //     io.println("🐛 DEBUG: Sending reply to comment 6")
  //     process.send(client, models.ClientReplyToComment(1, 6, "I agree!"))
  //   })

  io.println("🐛 DEBUG: Comment operations dispatched!")
}

fn execute_voting_operations(clients, upvotes, downvotes) {
  let upvote_clients = list.take(clients, upvotes)
  let downvote_clients = list.take(clients, downvotes)

  list.each(upvote_clients, fn(client) {
    process.send(client, models.UpvotePost(1))
  })

  list.each(downvote_clients, fn(client) {
    process.send(client, models.DownvotePost(1))
  })
}

fn execute_dm_operations_simple(clients, dms) {
  let dm_clients = list.take(clients, dms)

  list.each(dm_clients, fn(client) {
    process.send(
      client,
      models.SendDirectMessage("admin", "Hello from simulation!"),
    )
  })
  // Skip DM replies to avoid complexity
}

fn execute_feed_operations(clients, count) {
  let feed_clients = list.take(clients, count)
  list.each(feed_clients, fn(client) {
    process.send(client, models.FetchFeed(10))
  })
}

fn execute_connection_operations(clients, disconnect_count, reconnect_count) {
  let disconnect_clients = list.take(clients, disconnect_count)

  list.each(disconnect_clients, fn(client) {
    process.send(client, models.Disconnect)
  })

  process.sleep(500)

  list.each(disconnect_clients, fn(client) {
    process.send(client, models.Connect)
  })
}

fn execute_leave_operations(clients, count) {
  let leave_clients = list.take(clients, count)
  list.each(leave_clients, fn(client) {
    process.send(client, models.LeaveSubreddit("programming"))
  })
}

fn get_timestamp() -> Int {
  now_ms()
}

fn setup_simulation_data_with_posts(
  engine: process.Subject(models.EngineMessage),
  config: SimulationConfig,
) {
  // Create admin user
  let admin_reply = process.new_subject()
  process.send(engine, models.RegisterUser("admin", admin_reply))
  let _ = process.receive(admin_reply, 1000)

  // Create subreddits
  let base_subreddits = [
    "programming",
    "gaming",
    "news",
    "music",
    "sports",
    "cooking",
    "art",
    "science",
    "movies",
    "books",
  ]
  list.each(base_subreddits, fn(sub_name) {
    let sub_reply = process.new_subject()
    process.send(engine, models.CreateSubReddit(sub_name, "admin", sub_reply))
    let _ = process.receive(sub_reply, 1000)
  })

  // Create 5 initial posts for commenting
  io.println("Creating 5 initial posts...")
  let initial_posts = [
    "Welcome to our Reddit simulation!",
    "This is a test post about programming",
    "Gaming discussion thread",
    "Latest news and updates",
    "Music recommendations",
  ]

  list.each(initial_posts, fn(content) {
    let post_reply = process.new_subject()
    process.send(
      engine,
      models.CreatePost("admin", "programming", content, False, post_reply),
    )
    let _ = process.receive(post_reply, 1000)
  })

  io.println("Initial posts created (IDs 1-5)")
}

fn create_simulation_clients(
  count: Int,
  engine: process.Subject(models.EngineMessage),
  acc: List(process.Subject(models.ClientMessage)),
) -> List(process.Subject(models.ClientMessage)) {
  case count {
    0 -> acc
    _ -> {
      let client_id = int.to_string(count)
      case client.start_client(client_id, engine) {
        Ok(client_subject) -> {
          create_simulation_clients(count - 1, engine, [
            client_subject,
            ..acc
          ])
        }
        Error(_) -> {
          create_simulation_clients(count - 1, engine, acc)
        }
      }
    }
  }
}

fn connect_clients_in_batches(
  clients: List(process.Subject(models.ClientMessage)),
  total_count: Int,
) {
  let batch_size = case total_count {
    n if n < 100 -> 25
    n if n < 500 -> 50
    _ -> 100
  }

  connect_batches(clients, batch_size, 1)
}

fn connect_batches(
  clients: List(process.Subject(models.ClientMessage)),
  batch_size: Int,
  batch_num: Int,
) {
  case clients {
    [] -> Nil
    _ -> {
      let batch = list.take(clients, batch_size)
      let remaining = list.drop(clients, batch_size)

      list.each(batch, fn(client) { process.send(client, models.Connect) })

      process.sleep(200)
      connect_batches(remaining, batch_size, batch_num + 1)
    }
  }
}

fn get_final_stats(
  engine: process.Subject(models.EngineMessage),
) -> models.EngineStats {
  let stats_reply = process.new_subject()
  process.send(engine, models.GetStats(stats_reply))

  case process.receive(stats_reply, 5000) {
    Ok(stats) -> stats
    Error(_) ->
      models.EngineStats(
        total_users: 0,
        total_posts: 0,
        total_subreddits: 0,
        total_messages: 0,
        total_comments: 0,
        user_stats: dict.new(),
        simulation_time: 0,
        total_operations: 0,
        operations_per_second: 0.0,
        upvote_count: 0,
        downvote_count: 0,
      )
  }
}

fn print_simulation_results(results: SimulationResults) {
  io.println("\n SIMULATION RESULTS")
  io.println("=====================")
  io.println("Users: " <> int.to_string(results.config.user_count))
  io.println(
    "Time: " <> int.to_string(results.time_taken_ms / 1000) <> " seconds",
  )
  io.println("Ops/Second: " <> float.to_string(results.operations_per_second))
  io.println("Posts: " <> int.to_string(results.actual_stats.total_posts))
  io.println(
    "Comments: " <> int.to_string(results.actual_stats.total_comments),
  )
  io.println(
    "Subreddits: " <> int.to_string(results.actual_stats.total_subreddits),
  )
  io.println(
    "Votes: "
    <> int.to_string(
      results.actual_stats.upvote_count + results.actual_stats.downvote_count,
    ),
  )
  io.println(
    "Total Operations: "
    <> int.to_string(results.actual_stats.total_operations),
  )
}

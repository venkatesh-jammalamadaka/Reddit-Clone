import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/string

import reddit/engine
import reddit/models
import reddit/simulator

const client_count = 100

const simulation_duration_ms = 60_000

const stats_interval_ms = 10_000

pub fn main() {
  io.println("Reddit Clone Engine Starting...")
  io.println("=====================================")

  let assert Ok(engine_subject) = engine.start_engine()

  io.println("✓ Engine started")

  let assert Ok(simulator_subject) = simulator.start_simulator(engine_subject)

  io.println("✓ Simulator started")

  process.send(simulator_subject, models.StartSimulation(client_count))

  io.println(
    "✓ Simulation started with " <> int.to_string(client_count) <> " clients",
  )
  io.println(
    "✓ Running for "
    <> int.to_string(simulation_duration_ms / 1000)
    <> " seconds...",
  )

  schedule_stats_collection(simulator_subject, 0)

  process.sleep(simulation_duration_ms)

  let stats_reply = process.new_subject()
  process.send(simulator_subject, models.CollectStats(stats_reply))

  case process.receive(stats_reply, 5000) {
    Ok(final_stats) -> {
      io.println(simulator.format_stats(final_stats))
    }
    Error(_) -> {
      io.println("Failed to collect final stats")
    }
  }

  io.println("=====================================")
  io.println(" Simulation completed")
}

fn schedule_stats_collection(
  simulator_subject: process.Subject(models.SimulatorMessage),
  count: Int,
) {
  case count >= simulation_duration_ms / stats_interval_ms {
    True -> {
      Nil
    }
    False -> {
      process.sleep(stats_interval_ms)

      let stats_reply = process.new_subject()
      process.send(simulator_subject, models.CollectStats(stats_reply))

      case process.receive(stats_reply, 5000) {
        Ok(stats) -> {
          print_stats(stats, count + 1)
        }
        Error(_) -> {
          io.println(
            "Failed to collect stats for sample " <> int.to_string(count + 1),
          )
        }
      }

      schedule_stats_collection(simulator_subject, count + 1)
    }
  }
}

fn print_stats(stats: models.SimulationStats, sample: Int) {
  let runtime_sec = stats.runtime_ms / 1000

  io.println("\n Stats Sample #" <> int.to_string(sample))
  io.println("  Runtime: " <> int.to_string(runtime_sec) <> " seconds")
  io.println(
    "  Active clients: "
    <> int.to_string(stats.active_clients)
    <> "/"
    <> int.to_string(stats.client_count),
  )
  io.println(
    "  Total operations: " <> int.to_string(stats.engine_stats.total_operations),
  )
  io.println("  Users: " <> int.to_string(stats.engine_stats.total_users))
  io.println(
    "  Subreddits: " <> int.to_string(stats.engine_stats.total_subreddits),
  )
  io.println("  Posts: " <> int.to_string(stats.engine_stats.total_posts))
  io.println("  Comments: " <> int.to_string(stats.engine_stats.total_comments))
  io.println(
    "  Direct messages: " <> int.to_string(stats.engine_stats.total_messages),
  )
}

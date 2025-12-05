// src/reddit/simulator.gleam
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/pair
import gleam/result
import gleam/string

import reddit/client
import reddit/models.{
  type ClientMessage, type ClientStats, type Comment, type DM,
  type EngineMessage, type EngineStats, type Post, type SimulationStats,
  type SimulatorMessage, type SubReddit, type UserDataType,
}

/// The simulator state
pub type SimulatorState {
  SimulatorState(
    engine: process.Subject(EngineMessage),
    clients: Dict(String, process.Subject(ClientMessage)),
    start_time: Int,
    client_count: Int,
  )
}

/// Initialize a new simulator
pub fn init_simulator(engine: process.Subject(EngineMessage)) -> SimulatorState {
  SimulatorState(
    engine: engine,
    clients: dict.new(),
    start_time: get_timestamp(),
    client_count: 0,
  )
}

/// Get an incrementing timestamp
fn get_timestamp() -> Int {
  // Use process creation time as base and add some variation
  let base = 1_699_522_800
  let pid_num = case process.self() {
    _pid -> base % 999_999
  }
  base + pid_num
}

/// Generate a random number in range [min, max]
fn random(min: Int, max: Int) -> Int {
  let range = max - min + 1
  let seed = get_timestamp()
  min + seed % range
}

/// Handle simulator messages
/// Handle simulator messages
pub fn handle_simulator_message(
  message: SimulatorMessage,
  state: SimulatorState,
) -> actor.Next(SimulatorMessage, SimulatorState) {
  case message {
    // Setup
    models.StartSimulation(client_count) -> {
      io.println(
        "Starting simulation with "
        <> int.to_string(client_count)
        <> " clients...",
      )

      let clients = create_clients(client_count, state.engine, dict.new(), 0)

      let updated_state =
        SimulatorState(..state, clients: clients, client_count: client_count)

      let client_list = dict.to_list(clients)
      let connect_count = client_count * 8 / 10

      list.take(client_list, connect_count)
      |> list.each(fn(client_pair) {
        let #(_, client) = client_pair
        process.send(client, models.Connect)
      })

      io.println("Started " <> int.to_string(client_count) <> " clients.")
      actor.continue(updated_state)
    }

    models.CollectStats(reply_to) -> {
      let engine_stats_reply = process.new_subject()
      process.send(state.engine, models.GetStats(engine_stats_reply))

      let engine_stats = case process.receive(engine_stats_reply, 1000) {
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

      let runtime = get_timestamp() - state.start_time

      let simulation_stats =
        models.SimulationStats(
          client_count: state.client_count,
          active_clients: dict.size(state.clients),
          engine_stats: engine_stats,
          client_stats: [],
          runtime_ms: runtime,
          posts_per_client: 0.0,
          comments_per_client: 0.0,
          average_karma: 0.0,
          start_time: state.start_time,
        )

      process.send(reply_to, simulation_stats)
      actor.continue(state)
    }

    _ -> {
      actor.continue(state)
    }
  }
}

fn create_clients(
  count: Int,
  engine: process.Subject(EngineMessage),
  clients: Dict(String, process.Subject(ClientMessage)),
  current_count: Int,
) -> Dict(String, process.Subject(ClientMessage)) {
  case count {
    0 -> clients
    _ -> {
      let client_id = int.to_string(current_count + 1)

      let result = client.start_client(client_id, engine)

      case result {
        Ok(client_subject) -> {
          let updated_clients =
            dict.insert(clients, client_id, client_subject)

          create_clients(count - 1, engine, updated_clients, current_count + 1)
        }
        Error(_) -> {
          create_clients(count - 1, engine, clients, current_count)
        }
      }
    }
  }
}

pub fn start_simulator(
  engine: process.Subject(EngineMessage),
) -> Result(process.Subject(SimulatorMessage), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: fn() {
      let state = init_simulator(engine)
      actor.Ready(state, process.new_selector())
    },
    init_timeout: 1000,
    loop: handle_simulator_message,
  ))
}

pub fn format_stats(stats: SimulationStats) -> String {
  let runtime_sec = stats.runtime_ms / 1000

  string.concat([
    "\n Final Simulation Results",
    "\n=====================================",
    "\n  Total runtime: " <> int.to_string(runtime_sec) <> " seconds",
    "\n  Total clients: " <> int.to_string(stats.client_count),
    "\n  Active clients at end: " <> int.to_string(stats.active_clients),
    "\n=====================================",
  ])
}

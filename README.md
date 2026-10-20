# CAW (Crows Against World) / CAH Clone
This is an Elixir/Phoenix implementation of an online Cards Against Humanity game.

## Architecture
- There's a GenServer handling everything on the server-side. Phoenix LiveView handles the templating, of course.
- Disconnects (e.g., closing the tab) start a grace timer with `Process.send_after()`, which eventually will remove players from the game.
- Cards are sourced from the public list in a plain-text format, which is then read at compile-time.
- The game is essentially a big state machine, with phases moving on based on specific criteria.
- Has a custom JS hook for moving through multiple cards as the Czar.
- Relatively easy to extend.

## Running
Simply run `mix phx.server` if you want the development server to run. (Of course, you will need Elixir/Mix installed.)

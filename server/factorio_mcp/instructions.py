INSTRUCTIONS = """\
This server reads live data from a Factorio 2.1 game (with mods) through the factorio-mcp mod. \
It is strictly read-only: nothing here can change the game.

Rules:
- The game runs mods and modded planets. Get the mod list from server_status; do not assume vanilla.
- Take numbers (recipes, crafting speeds, ratios) only from game_reference, never \
from memory. The Factorio wiki is fine for explaining mechanics, but it may lag behind 2.1 and \
knows nothing about modded content.
- You can see only your own inventory, never another player's. Positions of all players are visible.
- A tool about a place takes a [gps=x,y,surface] tag, a player's name, or nothing for your own \
position.
- Whole-base (base_*) and big-area scans run in small steps over game ticks, so players do not \
notice them, and can take a minute or two. If a tool answers status "running" with a job_id, call \
the same tool again with that job_id until it returns the result.
- Long lists come in pages: pass offset and limit for more.
- If the data is not available, say so and do not invent it.
"""

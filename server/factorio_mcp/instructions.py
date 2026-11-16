INSTRUCTIONS = """\
This server reads live data from a Factorio 2.1 game (with mods) through the factorio-mcp mod. \
It is strictly read-only: nothing here can change the game.

Rules:
- The game runs mods and modded planets. Get the mod list from server_status; do not assume vanilla.
- Take numbers (recipes, crafting speeds, ratios) only from the game's own reference tools, never \
from memory. The Factorio wiki is fine for explaining mechanics, but it may lag behind 2.1 and \
knows nothing about modded content.
- You can see only your own inventory, never another player's. Positions of all players are visible.
- If the data is not available, say so and do not invent it.
"""

# Claude Desktop on Windows

Claude Desktop's built-in "connectors" run in Anthropic's cloud, so they cannot reach a service
that lives on a private network. Instead Claude Desktop starts a small local program, `mcp-remote`,
that forwards to the service over HTTP. You need the service address and your personal token from
whoever runs the service.

1. **Install Node.js 18 or newer** (nodejs.org, the LTS installer). Claude Desktop uses the Node.js
   installed on the system, so restart Claude Desktop after installing.
2. **Make sure the service address works.** Open `http://<service-address>:<port>/health` in a
   browser: it must show `{"status":"ok"}`. If not, fix the network access first (for example sign
   in to the VPN you were given).
3. **Edit the Claude Desktop config:** Settings, Developer, Edit Config opens `claude_desktop_config.json`.
   Add the server (keep any servers you already have):

   ```json
   {
     "mcpServers": {
       "factorio": {
         "command": "npx",
         "args": [
           "mcp-remote",
           "http://<service-address>:<port>/mcp",
           "--allow-http",
           "--header",
           "Authorization:${FACTORIO_MCP_AUTH}"
         ],
         "env": {
           "FACTORIO_MCP_AUTH": "Bearer <your-token>"
         }
       }
     }
   }
   ```

   - `--allow-http` is needed because the service speaks plain HTTP to a non-localhost address.
     Use it only on a private network where the traffic cannot be intercepted.
   - The header is passed through an environment variable and written as `Authorization:${...}`
     with no spaces around the colon, because Claude Desktop on Windows does not escape spaces in
     `args` (the `Bearer <token>` value, which has a space, is safe inside `env`).
4. **Restart Claude Desktop** completely (quit it from the tray icon, then start it again).
5. **Check:** the `factorio` server appears in the tools list. Ask: "Who is online on the Factorio
   server and which mods are installed?"

The token is personal. Do not share it; ask the server owner to revoke and reissue it if it leaks.

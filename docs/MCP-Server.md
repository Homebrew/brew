---
last_review_date: "2025-07-18"
---

# Homebrew's MCP Server

Homebrew's MCP Server is the official MCP ([Model Context Protocol](https://modelcontextprotocol.io/)) server for Homebrew, enabling AI assistants like Cursor, VS Code or Claude Code to interact with Homebrew directly, providing tools for various Homebrew commands e.g. `brew search`, `brew install`, `brew uninstall`, `brew upgrade`.

You don't need to do anything to install it.
It's provided by default with Homebrew through the `brew mcp-server` command.

## Usage

Run `brew mcp-server` to launch the Homebrew MCP Server.

```bash
$ brew mcp-server
==> Started Homebrew MCP server...
```

Press Ctrl-D or Ctrl-C to terminate it.

## Configuration

### Example configuration for [Cursor](https://www.cursor.com/)

```json
{
  "mcpServers": {
    "Homebrew": {
      "command": "brew mcp-server"
    }
  }
}
```

### Example configuration for [VSCode](https://code.visualstudio.com/)

```json
{
  "mcp": {
    "servers": {
      "Homebrew": {
        "type": "stdio",
        "command": "brew",
        "args": ["mcp-server"]
      }
    }
  }
}
```

### Example configuration for [Zed](https://github.com/zed-industries/zed)

```json
{
  "context_servers": {
  "Homebrew": {
    "source": "custom",
    "command": "brew",
    "args": ["mcp-server"],
    "env": {}
  }
  }
}
```

### Example configuration for [Claude Desktop](https://claude.ai/download)

```json
{
  "mcpServers": {
    "Homebrew": {
      "command": "brew mcp-server"
    }
  }
}
```

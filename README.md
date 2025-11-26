# 🚀 Remote MCP Server Demo (Python)

This guide shows you how to build a **remote MCP (Model Context Protocol) server** from scratch — starting with a simple *Hello World* and evolving into a complete **Todo-Management MCP Server**, accessible over **HTTP** and deployable to **Azure Container Apps**.

We follow an **incremental, hands-on** approach to demonstrate real-world MCP development.

---

# 📌 Table of Contents

* [Section 1 — Project Setup & Basic MCP Server](#section-1--project-setup--basic-mcp-server)
* [Section 2 — Real Functionality: Todo Management](#section-2--real-functionality-todo-management)
* [Section 3 — MCP Tools & HTTP Server](#section-3--mcp-tools--http-server)
* [Section 4 — Deploying to Azure Container Apps](#section-4--deploying-to-azure-container-apps)
* [Closing Summary](#closing-summary)
* [Resources](#resources)

---

# Section 1 — Project Setup & Basic MCP Server

## 🛠️ Demo Commands

### 1. Initialize a new Python project with **uv**

```bash
uv init remote-mcp-demo
cd remote-mcp-demo
```

### 2. Verify setup

```bash
uv run hello.py
```

### 3. Install Python MCP SDK

```bash
uv add "mcp[cli]"
```

---

## ▶️ Your First MCP Server

### 4. Create the server file

```bash
mkdir src
```

**src/dummy_server.py**

```python
from mcp.server.fastmcp import FastMCP

# Create an MCP server using FastMCP
mcp = FastMCP("dummy-mcp-server")

@mcp.tool()
def hello_world(name: str) -> str:
    """Simple hello world tool"""
    return f"Hello, {name}!"
```

### 5. Test the MCP server

```bash
uv run mcp dev src/dummy_server.py
```

---

# Section 2 — Real Functionality: Todo Management

## 📦 Adding Business Logic (SQLite + Pydantic)

### Install Pydantic

```bash
uv add pydantic
```

---

Create file: src/db.py
Install Pydantic for data validation
uv add pydantic

db.py
import sqlite3
import os
from typing import List, Dict, Any, Optional
from pydantic import BaseModel, Field, field_validator
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("db")

class TodoSchema(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)
    id: Optional[int] = Field(None, gt=0)
    
    @field_validator('title')
    @classmethod
    def validate_title(cls, v: str) -> str:
        if not v or v.strip() == '':
            raise ValueError('Title cannot be empty or contain only whitespace')
        return v.strip()

DB_NAME = "todos.db"

def init_db():
    """Initialize the SQLite database"""
    try:
        conn = sqlite3.connect(DB_NAME)
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS todos (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                text TEXT NOT NULL,
                completed INTEGER NOT NULL DEFAULT 0
            )
        """)
        conn.commit()
        conn.close()
        logger.info(f'Database "{DB_NAME}" initialized.')
    except Exception as error:
        logger.error(f'Error initializing database "{DB_NAME}": {error}')

# Initialize database on import
init_db()

def add_todo(text: str) -> Dict[str, Any]:
    """Add a new todo to the database"""
    logger.info(f"Adding TODO: {text}")
    
    # Validate input
    validated_input = TodoSchema(title=text)
    
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    cursor.execute("INSERT INTO todos (text) VALUES (?)", (validated_input.title,))
    lastInsertRowid = cursor.lastrowid
    conn.commit()
    conn.close()
    return {"lastInsertRowid": lastInsertRowid}

def list_todos() -> List[Dict[str, Any]]:
    """Get all todos from the database"""
    logger.info("Listing all TODOs")
    
    conn = sqlite3.connect(DB_NAME)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM todos ORDER BY id")
    rows = cursor.fetchall()
    conn.close()
    return [dict(row) for row in rows]

def complete_todo(todo_id: int) -> Dict[str, Any]:
    """Mark a todo as completed"""
    logger.info(f"Completing TODO: {todo_id}")
    
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    cursor.execute("UPDATE todos SET completed = 1 WHERE id = ?", (todo_id,))
    changes = cursor.rowcount
    conn.commit()
    conn.close()
    return {"changes": changes}

def delete_todo(todo_id: int) -> Optional[Dict[str, Any]]:
    """Delete a todo from the database"""
    logger.info(f"Deleting TODO: {todo_id}")
    
    conn = sqlite3.connect(DB_NAME)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    # Get the todo before deleting
    cursor.execute("SELECT * FROM todos WHERE id = ?", (todo_id,))
    row = cursor.fetchone()
    
    if row:
        cursor.execute("DELETE FROM todos WHERE id = ?", (todo_id,))
        conn.commit()
        conn.close()
        return dict(row)
    
    conn.close()
    return None

def update_todo_text(todo_id: int, text: str) -> Optional[Dict[str, Any]]:
    """Update the text of a todo"""
    logger.info(f"Updating TODO {todo_id}: {text}")
    
    # Validate input
    validated_input = TodoSchema(title=text, id=todo_id)
    
    conn = sqlite3.connect(DB_NAME)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    cursor.execute("UPDATE todos SET text = ? WHERE id = ?", (validated_input.title, todo_id))
    
    if cursor.rowcount > 0:
        cursor.execute("SELECT * FROM todos WHERE id = ?", (todo_id,))
        row = cursor.fetchone()
        conn.commit()
        conn.close()
        return dict(row) if row else None
    
    conn.close()
    return None
---

# Section 3 — MCP Tools & HTTP Server

## 🧰 Create MCP Tools

### File: `src/tools.py`

```python
from mcp.server.fastmcp import FastMCP
from typing import List
from db import (
    add_todo,
    list_todos,
    complete_todo,
    delete_todo,
    update_todo_text,
)

# Create an MCP server
mcp = FastMCP("todo-mcp-server")

@mcp.tool()
def add_todo_tool(title: str) -> List[str]:
    info = add_todo(title)
    return [f"Added TODO: {title} (id: {info['lastInsertRowid']})"]

@mcp.tool()
def list_todos_tool() -> List[str]:
    todos = list_todos()
    if not todos:
        return ["No TODOs found."]
    return [
        f"TODO: {todo['text']} (id: {todo['id']}){' [completed]' if todo['completed'] else ''}"
        for todo in todos
    ]

@mcp.tool()
def complete_todo_tool(id: int) -> List[str]:
    info = complete_todo(id)
    if info["changes"] == 0:
        return [f"TODO with id {id} not found."]
    return [f"TODO with id {id} marked as completed."]

@mcp.tool()
def delete_todo_tool(id: int) -> List[str]:
    row = delete_todo(id)
    if not row:
        return [f"TODO with id {id} not found."]
    return [f"Deleted TODO: {row['text']} (id: {id})"]

@mcp.tool()
def update_todo_text_tool(id: int, text: str) -> List[str]:
    row = update_todo_text(id, text)
    if not row:
        return [f"TODO with id {id} not found."]
    return [f"Updated text for todo with id {id} to \"{text}\""]
```

### Test with:

```bash
uv run mcp dev src/tools.py
```

---

## 🧪 Testing With VS Code Copilot

Add to your VS Code `settings.json`:

```json
"my-todo-mcp-server": {
    "type": "stdio",
    "command": "uv",
    "args": [
        "run",
        "mcp",
        "run",
        "/path/to/your/project/src/tools.py"
    ]
}
```

---

## 🌐 Convert to HTTP (Remote MCP Server)

```bash
cp src/tools.py src/streamable_http_server.py
```

Add at bottom of the file:

```python
if __name__ == "__main__":
    mcp.run(transport="streamable-http")
```

### Run the HTTP server

```bash
uv run python src/streamable_http_server.py
```

### Test via Inspector

```bash
npx @modelcontextprotocol/inspector http://127.0.0.1:3000/mcp
```

---

# Section 4 — Deploy to Azure Container Apps

## ☁️ Taking It to Production

### 1. Install Azure Developer CLI

```bash
brew tap azure/azd && brew install azd
```

### 2. Login

```bash
azd auth login
```

### 3. Provision + Deploy

```bash
azd up
```

---

## 📘 Infrastructure Overview

The **infra/** folder contains:

* `resources.bicep` → Container App, ACR, monitoring
* `apim-api/` → API Management configuration
* `main.bicep` → orchestrates the deployment

### Test your deployed server

```bash
npx @modelcontextprotocol/inspector https://mcp-container-py.blacksea-1835d48f.eastus.azurecontainerapps.io/mcp
```

---

# Closing Summary

## ✅ What We Built

* Created a basic **MCP server**
* Implemented **5 Todo CRUD tools**
* Converted from **stdio → HTTP**
* Deployed to **Azure Container Apps** for global availability

## 🚀 Next Steps

* Add richer business logic
* Implement authentication & RBAC
* Enable rate limiting / caching
* Add health checks & monitoring

---

# Resources

* Demo Code: [https://github.com/Mossaka/remote-mcp-python-demo](https://github.com/Mossaka/remote-mcp-python-demo)
* MCP Authorization Deep Dive: [https://github.blog/ai-and-ml/generative-ai/how-to-build-secure-and-scalable-remote-mcp-servers/](https://github.blog/ai-and-ml/generative-ai/how-to-build-secure-and-scalable-remote-mcp-servers/)
* MCP Python SDK: [https://github.com/modelcontextprotocol/python-sdk](https://github.com/modelcontextprotocol/python-sdk)
* MCP Specification: [https://spec.modelcontextprotocol.io/](https://spec.modelcontextprotocol.io/)
* Azure Container Apps: [https://learn.microsoft.com/en-us/azure/container-apps/](https://learn.microsoft.com/en-us/azure/container-apps/)
* Microsoft MCP Initiatives: [https://github.com/microsoft/mcp](https://github.com/microsoft/mcp)

---

If you want, I can also:

✅ Add badges (Python version, license, build status)
✅ Add architecture diagrams
✅ Add folder structure tree
✅ Generate a full `azd` template for this project

Just tell me!



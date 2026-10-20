#!/usr/bin/env python3
"""Exercise the actual CLI and MCP subprocess with synthetic files only."""
import json
import pathlib
import selectors
import subprocess
import sys
import tempfile
import uuid


def check(binary):
    with tempfile.TemporaryDirectory(prefix="ahm-management-cli-") as directory:
        home = pathlib.Path(directory)
        for name, body in [("one", "---\nname: one\ndescription: Synthetic skill\n---\nSafe fixture"),
                           ("two", "Missing frontmatter")]:
            document = home / ".agents/skills" / name / "SKILL.md"
            document.parent.mkdir(parents=True)
            document.write_text(body)
        grok_document = home / ".grok/skills/grok-example/SKILL.md"
        grok_document.parent.mkdir(parents=True)
        grok_document.write_text("---\nname: grok-example\ndescription: Grok fixture\n---\nFixture")
        added_roots = [
            ("antigravity", ".gemini/config/skills", "antigravity-app"),
            ("antigravity", ".gemini/antigravity-cli/skills", "antigravity-cli"),
            ("antigravity", ".gemini/antigravity/skills", "antigravity-legacy"),
            ("opencode", ".config/opencode/skills", "opencode-example"),
            ("pi", ".pi/agent/skills", "pi-example"),
            ("devin", ".config/devin/skills", "devin-example"),
            ("cursor", ".cursor/skills", "cursor-example"),
        ]
        for agent, root, name in added_roots:
            document = home / root / name / "SKILL.md"
            document.parent.mkdir(parents=True)
            document.write_text(f"---\nname: {name}\ndescription: Synthetic {agent}\n---\nFixture")
        domain = "ahm.cli.check." + uuid.uuid4().hex
        command = [binary, "--home", directory, "--domain", domain]

        def cli(*args, success=True):
            result = subprocess.run(command + list(args), capture_output=True, text=True, timeout=10)
            assert (result.returncode == 0) == success, result.stderr
            return json.loads(result.stdout if success else result.stderr)

        status = cli("status")
        assert status["skillCount"] == 10 and status["domain"] == domain
        assert {item["name"] for item in cli("list", "--agent", "grokBuild")["skills"]} == {"one", "two", "grok-example"}
        for agent, root, name in added_roots:
            filtered = cli("list", "--agent", agent)["skills"]
            assert name in {item["name"] for item in filtered}
            assert len(filtered) == 3
        assert len(status["roots"]) == 10
        items = cli("list")["skills"]
        installation = next(item for item in items if item["name"] == "one")["installations"][0]
        identity = installation["id"]
        assert installation["agents"] == ["codex", "grokBuild", "opencode", "pi", "devin", "cursor"]
        assert "Safe fixture" in cli("show", identity)["document"]
        assert cli("check")["review"]["findings"]
        assert cli("groups")["groups"] == []
        assert cli("list", "--limit", "1")["total"] == 10
        assert cli("list", "--offset", "1", "--limit", "1")["offset"] == 1
        cli("list", "--limit", "0", success=False)
        cli("show", "/etc/passwd", success=False)
        cli("request", "disable", "not-an-installation", success=False)
        assert cli("requests")["requests"] == []
        plan = cli("plan", "disable", identity)
        assert plan["applied"] is False and not plan["noChanges"]
        assert set(plan["affectedAgents"]) == {"codex", "grokBuild", "opencode", "pi", "devin", "cursor"}
        assert plan["sharedPathWarning"]
        assert cli("requests")["requests"] == []
        assert cli("plan", "enable", identity)["noChanges"]

        process = subprocess.Popen(command + ["mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)

        def send(value):
            process.stdin.write(json.dumps(value).encode() + b"\n")
            process.stdin.flush()

        def receive():
            assert selector.select(timeout=10), "MCP response timed out"
            line = process.stdout.readline()
            assert line, "MCP server exited unexpectedly"
            return json.loads(line)

        def rpc(identity, method, params=None):
            request = {"jsonrpc": "2.0", "id": identity, "method": method}
            if params is not None:
                request["params"] = params
            send(request)
            response = receive()
            assert response["id"] == identity
            return response

        try:
            assert rpc(0, "tools/list")["error"]["code"] == -32000
            assert rpc(1, "ping")["result"] == {}
            initialized = rpc(2, "initialize", {"protocolVersion": "future-version", "capabilities": {},
                                               "clientInfo": {"name": "synthetic-check", "version": "1"}})
            assert initialized["result"]["protocolVersion"] == "2025-11-25"
            send({"jsonrpc": "2.0", "method": "notifications/initialized"})
            tools = rpc(3, "tools/list")["result"]["tools"]
            assert len(tools) == 8 and all("_command" not in tool for tool in tools)
            assert all("apply" not in tool["name"] and "install" not in tool["name"] for tool in tools)
            request_tool = next(tool for tool in tools if tool["name"] == "ahm_request")
            assert request_tool["annotations"]["readOnlyHint"] is False
            assert request_tool["annotations"]["destructiveHint"] is False
            assert rpc(4, "tools/call", {"name": "ahm_status"})["result"]["structuredContent"]["skillCount"] == 10
            assert rpc(5, "tools/call", {"name": "ahm_show", "arguments": {"installationID": identity}})["result"]["isError"] is False
            assert rpc(6, "tools/call", {"name": "ahm_request", "arguments": {"installationIDs": [identity], "enabled": 1}})["result"]["isError"] is True
            assert rpc(7, "tools/call", {"name": "ahm_status", "arguments": {"shell": "arbitrary"}})["error"]["code"] == -32602
            assert rpc(8, "tools/call", {"name": "unknown"})["error"]["code"] == -32602
            assert rpc(9, "unknown")["error"]["code"] == -32601
            assert rpc(10, "tools/call", {"name": "ahm_list", "arguments": {"limit": True}})["result"]["isError"] is True
            result = rpc(11, "tools/call", {"name": "ahm_request", "arguments": {"installationIDs": [identity], "enabled": False,
                                                                                   "title": "Synthetic MCP request"}})["result"]
            assert result["isError"] is False, result
            request_id = result["structuredContent"]["requestID"]
            assert result["structuredContent"]["applied"] is False
            assert (home / ".agents/skills/one/SKILL.md").exists()
            requests = cli("requests")["requests"]
            assert len(requests) == 1 and requests[0]["id"] == request_id
            assert requests[0]["state"] == "awaiting_app_review"
            process.stdin.write(b"not-json\n")
            process.stdin.flush()
            assert receive()["error"]["code"] == -32700
            send([])
            assert receive()["error"]["code"] == -32600
            assert rpc(12, "tools/list", ["invalid"])["error"]["code"] == -32602
        finally:
            process.stdin.close()
            process.wait(timeout=10)
            selector.close()
            assert process.returncode == 0 and process.stderr.read() == b""
        oversized = subprocess.run(command + ["mcp"], input=b"x" * 1_048_577 + b"\n", capture_output=True, timeout=10)
        assert oversized.returncode != 0 and b"1 MiB" in oversized.stderr
        assert (home / ".agents/skills/one/SKILL.md").read_text().endswith("Safe fixture")
    print("PASS: actual CLI/MCP initialization, negotiation, schemas, paging, documents, local checks, strict inputs, safe intent queue, JSON-RPC errors and message bounds; no login or real skill changes")


if __name__ == "__main__":
    check(sys.argv[1])

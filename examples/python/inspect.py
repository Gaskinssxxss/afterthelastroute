#!/usr/bin/env python3
"""Collect real BGP state and endpoint reachability via the Docker CLI."""
import json
import re
import subprocess


def docker_exec(node: str, *args: str) -> str:
    try:
        result = subprocess.run(
            ["docker", "exec", f"clab-routing-lab-{node}", *args],
            check=True,
            text=True,
            capture_output=True,
            timeout=20,
        )
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or "Docker command returned a non-zero exit status").strip()
        raise SystemExit(f"FAIL: Docker command failed for node {node}: {detail}") from exc
    except subprocess.TimeoutExpired as exc:
        raise SystemExit(f"FAIL: Docker command timed out for node {node}") from exc
    return result.stdout


def main() -> None:
    bgp = json.loads(docker_exec("r1", "vtysh", "-c", "show ip bgp summary json"))
    routes = json.loads(docker_exec("r1", "vtysh", "-c", "show ip route 10.20.40.0/24 json"))
    ping = docker_exec("client-a", "ping", "-c", "2", "-W", "2", "10.20.40.10")
    peer_map = bgp.get("ipv4Unicast", {}).get("peers", {})
    route_list = routes.get("10.20.40.0/24", [])
    received = re.search(r"(\d+) packets received", ping)
    result = {"bgp_summary": bgp, "remote_prefix": routes, "ping": ping.strip()}
    if not any(peer.get("state") == "Established" for peer in peer_map.values()):
        raise SystemExit("FAIL: no established BGP peer reported")
    if not any(route.get("protocol") == "bgp" and route.get("installed") for route in route_list):
        raise SystemExit("FAIL: remote prefix is not installed as a BGP route")
    if not received or int(received.group(1)) != 2:
        raise SystemExit("FAIL: expected route or endpoint response missing")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

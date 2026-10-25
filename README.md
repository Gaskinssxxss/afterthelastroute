# afterthelastroute

*Keep packets moving. Break a path, watch the network find another.*

`afterthelastroute` is an isolated, reusable IPv4 routing lab built with Containerlab, Docker and FRRouting. It connects four routers across two autonomous systems and two Linux endpoints, giving you a small place to experiment with routing, automation and failure recovery. It is a testbed, not a substitute for production hardware.

**Validation status:** deployed and validated on the Ubuntu host described in [validation status](docs/validation-status.md). The acceptance suite passed 27 checks, including six real routing incidents and recoveries, plus Ansible and Python integrations. Other Linux hosts and GitHub Actions have not yet been tested end to end.

## Topology

```text
 Client-A                                                        Client-B
 10.10.10.10/24                                                  10.20.40.10/24
     |                                                                 |
    R1 (AS65010) === OSPF === R2 (AS65010)    R3 (AS65020) === OSPF === R4 (AS65020)
      \\________________ eBGP primary ________________/                  
       \________________ eBGP alternate ______________________________/
```

R1/R2 and R3/R4 each form an OSPF area 0 domain. Each AS uses iBGP between its routers, with loopbacks as BGP update sources and OSPF reachability to those loopbacks. Two eBGP links join the ASes. BGP prefers the direct eBGP-learned route over the iBGP alternative; the second eBGP link and internal OSPF path provide failover. Endpoint prefixes are originated by their edge routers. The policy exercise prefix `198.51.100.0/24` is explicitly rejected at the AS65020-to-AS65010 boundary.

| Node | Role | Loopback | Endpoint/link addresses |
|---|---|---|---|
| r1 | AS65010 edge | 10.255.0.1/32 | client-a 10.10.10.1/24; r2 10.0.12.1/30; r4 10.0.14.1/30 |
| r2 | AS65010 core | 10.255.0.2/32 | r1 10.0.12.2/30; r3 10.0.23.1/30 |
| r3 | AS65020 core | 10.255.0.3/32 | r2 10.0.23.2/30; r4 10.0.34.1/30 |
| r4 | AS65020 edge | 10.255.0.4/32 | r3 10.0.34.2/30; r1 10.0.14.2/30; client-b 10.20.40.1/24 |
| client-a | Linux endpoint | — | 10.10.10.10/24, gateway 10.10.10.1 |
| client-b | Linux endpoint | — | 10.20.40.10/24, gateway 10.20.40.1 |

Containerlab management uses an isolated Docker bridge and no published host ports. The topology pins its management subnet to `172.31.250.0/24`; preflight checks host routes and Docker networks for overlap before deployment. Router management IPs are 172.31.250.11–14.

## Prerequisites

- Linux amd64 with network namespaces, veth, bridge and Docker bridge support.
- Docker Engine 24 or newer and permission to use its socket.
- Containerlab 0.80.0 or newer.
- `make`, `bash`, `iproute2`, `curl`, and Python 3.10+ for helper examples.
- For integration examples: Ansible Core 2.15+.

The implementation requires Containerlab `0.80.0` or newer (for topology schema validation) and pins FRR image `quay.io/frrouting/frr:10.2.1` plus Alpine `3.21.3`. Docker registry availability can change. No install script is executed by the project.

## Quick start

```bash
git clone <repository-url>
cd afterthelastroute
make preflight
make deploy
make validate
```

Containerlab deployment requires elevated network namespace and Docker capabilities. Run with a user authorized for the Docker socket and Containerlab's required privileges. Do not grant access to untrusted users: Docker access is effectively root access.

## Operations

| Command | Action |
|---|---|
| `make preflight` | Read-only compatibility, conflict and capacity checks |
| `make deploy` | Preflight and deploy only this topology |
| `make status` | Containerlab/Docker and protocol/endpoint status |
| `make validate` | Check baseline routing and end-to-end forwarding |
| `make acceptance` | Run all six real-state failure/recovery scenarios |
| `make incident NAME=bgp-neighbor` | Inject one named scenario |
| `make recover NAME=bgp-neighbor` | Restore the selected scenario |
| `make reset` | Destroy this topology and redeploy its checked-in baseline |
| `make evidence` | Save command outputs under ignored `evidence/` |
| `make destroy` | Destroy only this topology |

Scenario names: `bgp-neighbor`, `ospf-adjacency`, `route-withdrawal`, `link-failure`, `policy-rejection`, `reachability-loss`. Execute the full real-state sequence with `./tests/acceptance.sh`; it captures observations under `evidence/` and fails on unexpected outcomes.

## Access and external tools

Router/endpoint names are `clab-routing-lab-r1`, `...-r2`, `...-r3`, `...-r4`, `...-client-a`, `...-client-b`. Use native tools:

```bash
docker exec clab-routing-lab-r1 vtysh -c 'show ip bgp summary'
docker exec clab-routing-lab-r1 vtysh -c 'show ip ospf neighbor'
docker exec clab-routing-lab-r1 ip route
docker exec clab-routing-lab-client-a ping -c 3 10.20.40.10
```

The external examples can be run from the repository root after deployment:

```bash
ansible-playbook -i localhost, examples/ansible/inspect.yml
python3 examples/python/inspect.py
```

`examples/ansible/` shows Ansible invoking read-only FRR commands through Docker. `examples/python/` shows Python collecting JSON-formatted BGP state and endpoint reachability. Both require local Docker access; no custom API is introduced. A user-owned diagnostic container can be attached to the management bridge with `docker network connect routing-lab-mgmt <container>` while the lab exists. The network is for management-plane access; router data-plane transit links are separate point-to-point networks.

Management access is via Docker exec / the private management bridge. Data plane is the router interfaces and endpoint prefixes. FRR CLI is `vtysh`; Linux tools run through `docker exec`. A host-side external tool uses Docker CLI/socket access; a containerized external tool must join the lab management network. Do not publish management services to a host or public interface.

## Safety and security

The scripts use a fixed project topology name and check address conflicts. They do not alter host interfaces, host routes, firewall rules, global Docker settings, or unrelated containers. Preflight refuses a pre-existing lab container prefix or management network instead of replacing it. `destroy` delegates only to `containerlab destroy -t topology.clab.yml --cleanup`, which removes this lab's generated Containerlab directory too. `make reset` destroys this topology, restores active router configuration from the checked-in `configs/baseline/` copies, and redeploys. Review scripts before running with Docker privileges. Avoid putting credentials in configuration or evidence.

## Validation, known limitations

`tests/` contains real integration acceptance checks; they require a compatible Linux Docker host and image pulls. CI workflows are implemented, but have not been run on GitHub. Privileged integration is assigned to a disposable self-hosted runner. Measurements and acceptance records belong in ignored `evidence/` and identify the host and run time. Actual local evidence is summarized in [validation status](docs/validation-status.md).

Known limitations: IPv4 only; four-router fixed topology; external examples use Docker CLI transport rather than SSH/NETCONF; public hosted CI does not run privileged routing integration; management bridge subnet may require an explicitly reviewed topology edit if it conflicts on another host.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Contributions should preserve host isolation and add real integration evidence for changed routing behavior. License: MIT; the project makes no claim over upstream components, which retain their own licenses.

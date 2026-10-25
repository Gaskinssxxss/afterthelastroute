# Validation status

Recorded 2026-10-26 on the Ubuntu development host. The lab was deployed, exercised, destroyed, redeployed, and left running in a healthy baseline.

## Tested environment

- Ubuntu 24.04.4 LTS, x86_64, Linux 7.0.0-38-generic.
- Docker Engine/client 29.1.3.
- Containerlab 0.80.0.
- FRRouting container `quay.io/frrouting/frr:10.2.1` (daemon reports FRR 10.2.1_git).
- Alpine endpoint image `alpine:3.21.3`.
- Ansible Core 2.16.3 / Ansible 9.2.0.
- 16 logical CPUs, 30 GiB RAM, and about 294 GiB free workspace disk at final deployment.

This is one tested host. Other Linux distributions, CPU architectures, and Docker/Containerlab versions have not been runtime-tested.

## Acceptance results

| Capability | Result | Evidence |
|---|---|---|
| Containerlab topology schema, 6 nodes / 6 links | PASS | `containerlab validate -t topology.clab.yml` |
| Fresh deployment and baseline health | PASS | `evidence/final/deploy.txt`; fresh deploy also recorded after cleanup |
| OSPF Full, iBGP/eBGP Established, endpoint routes and kernel FIB | PASS | `evidence/final/acceptance.txt` |
| Six fault scenarios and recovery | PASS | `evidence/final/acceptance.txt`, 27 passing checks total |
| Rejected-prefix policy and route withdrawal | PASS | Real FRR RIB checks and endpoint traffic checks in acceptance output |
| Ansible external state query | PASS | `evidence/final/ansible.txt` (3 tasks, 0 failed) |
| Python structured BGP/route and reachability query | PASS | `evidence/final/python.json` |
| Python reports failure when R1 is unavailable | PASS | Acceptance suite stops the owned R1 container and confirms a clear non-zero failure |
| Reset, teardown with generated-state cleanup, and redeploy | PASS | Acceptance suite reset plus clean destroy/deploy cycle |
| Unrelated Docker resources and host state across final teardown | PASS | `evidence/final/host-safety/`; exact unrelated container/network identities, routes, interfaces, and non-lab firewall rules compared |
| Local shell/YAML/Python/security checks | PASS with one optional tool skipped | ShellCheck, Bash syntax, YAML parsing, Python compilation, manual secret-pattern scan; gitleaks was not installed |
| GitHub Actions execution | NOT RUN | Workflows are present; no GitHub run was started |

The final acceptance run reported **27 PASS, 0 FAIL**. The tests observe live FRR state, kernel routes, interface state, and endpoint packets; they do not use mocked routing state.

## Measured resource use

At the final `docker stats` sample with all six lab containers running (`evidence/20261025T175130Z/`):

- Four FRR routers used about 108.5 MiB RAM total; the two endpoints used about 1.6 MiB. Total observed use was about 110 MiB.
- CPU was 0% per container in that brief sample. This is not a sustained-load benchmark.
- Writable container layers totaled about 0.93 MiB. The reported image sizes were 87,345,110 bytes for FRR and 3,653,068 bytes for Alpine.
- Containerlab's create command completed in about 1 second. Protocol timers and scenario recovery times are recorded in `evidence/final/acceptance.txt`; the route withdrawal took 4 seconds to disappear in the final run, OSPF recovery took 11 seconds, and the path/endpoint checks recovered in 0–2 seconds.

Resource evidence is in `evidence/20261025T175130Z/`; earlier samples are retained in `evidence/` for comparison.

## Host safety and setup changes

The final before/after teardown comparison found no changes to unrelated container identities, Docker networks, host routes, non-lab interfaces, or non-lab firewall rules. Containerlab's management bridge and six lab veth interfaces disappeared on teardown; the lab-specific `/etc/hosts` entries, SSH fragment, and generated `clab-routing-lab/` directory were also removed. Earlier, the unrelated Nira service was observed restarting and creating its own network while the longer test session was in progress; the final short before/after teardown comparison showed its then-current identity and network unchanged.

With the user's authorization, Containerlab 0.80.0 and Ansible were installed on the host, and the account was added to the `docker` and `clab_admins` groups. The account may need a new login session for those group changes to apply to ordinary shells. Docker socket access is effectively administrator-level access.

## Repository and publication status

The repository is locally initialized, contains no commit yet, and has not been pushed. The MIT license and CI workflows are present. Local quality checks pass; GitHub-hosted workflow execution remains unverified. The lab is prepared for publication, but do not describe the CI workflows as having passed until they run on GitHub or the configured disposable self-hosted runner.

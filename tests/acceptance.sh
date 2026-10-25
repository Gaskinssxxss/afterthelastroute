#!/usr/bin/env bash
# Real-state acceptance suite. Requires the deployed lab and Docker access.
set -Eeuo pipefail
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
LAB=./scripts/lab
EVIDENCE="${EVIDENCE_DIR:-$PWD/evidence/acceptance-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$EVIDENCE"
pass() { printf 'PASS: %s\n' "$*" | tee -a "$EVIDENCE/results.txt"; }
fail() { printf 'FAIL: %s\n' "$*" | tee -a "$EVIDENCE/results.txt" >&2; exit 1; }
frr() { docker exec "clab-routing-lab-$1" vtysh -c "$2"; }
node() { docker exec "clab-routing-lab-$1" "${@:2}"; }
must_contain() {
  local pattern="$1" message="$2"; shift 2
  local output
  output=$("$@" 2>&1) || { printf '%s\n' "$output" >>"$EVIDENCE/observations.txt"; fail "command failed while checking: $message"; }
  printf '%s\n' "$output" | tee -a "$EVIDENCE/observations.txt" | grep -Eq "$pattern" || fail "$message"
  pass "$message"
}
must_not_contain() {
  local pattern="$1" message="$2"; shift 2
  local output
  output=$("$@" 2>&1) || { printf '%s\n' "$output" >>"$EVIDENCE/observations.txt"; fail "command failed while checking: $message"; }
  printf '%s\n' "$output" | tee -a "$EVIDENCE/observations.txt"
  if grep -Eq "$pattern" <<<"$output"; then fail "$message"; fi
  pass "$message"
}
wait_for() {
  local description="$1"; shift
  local start=$SECONDS
  until "$@" >/dev/null 2>&1; do
    (( SECONDS - start < 60 )) || fail "timed out waiting for $description"
    sleep 2
  done
  pass "$description (converged in $((SECONDS-start))s)"
}
peer_down() {
  local output
  output=$(frr r1 'show ip bgp summary') || return 2
  grep '^10\.0\.14\.2 ' <<<"$output" | awk '$10 !~ /^[0-9]+$/ {down=1} END {exit !down}'
}
route_absent() {
  local output
  output=$(frr r1 'show ip route 10.20.40.0/24') || return 2
  ! grep -q 'Known via "bgp"' <<<"$output"
}
ospf_absent() {
  local output
  output=$(frr r1 'show ip ospf neighbor') || return 2
  ! grep -q 'Full' <<<"$output"
}
primary_path() {
  local output
  output=$(frr r1 'show ip route 10.20.40.0/24') || return 2
  grep -q '10\.0\.14\.2' <<<"$output"
}
alternate_path() {
  local output
  output=$(frr r1 'show ip route 10.20.40.0/24') || return 2
  grep -q '10\.0\.12\.2' <<<"$output"
}
end_to_end() { node client-a ping -c 2 -W 2 10.20.40.10; }

"$LAB" validate | tee "$EVIDENCE/baseline.txt" || fail 'healthy baseline'
must_contain '65020' 'R1 has BGP peer output' frr r1 'show ip bgp summary'
must_contain 'Full' 'R1 OSPF adjacency reaches Full' frr r1 'show ip ospf neighbor'
must_contain 'Known via "bgp"' 'R1 installs the endpoint prefix in FRR' frr r1 'show ip route 10.20.40.0/24'
must_contain '10\.0\.14\.2' 'R1 uses the direct eBGP primary path at baseline' frr r1 'show ip route 10.20.40.0/24'
must_contain '10.20.40.0/24' 'Linux kernel has remote endpoint route' node r1 ip route show
must_not_contain 'Known via "bgp"' 'rejected prefix absent from R1' frr r1 'show ip route 198.51.100.0/24'

"$LAB" incident bgp-neighbor
wait_for 'the selected BGP peer leaves Established' peer_down
must_contain '10\.0\.12\.2' 'R1 selects the alternate route through R2' frr r1 'show ip route 10.20.40.0/24'
wait_for 'alternate route continues endpoint forwarding' end_to_end
"$LAB" recover bgp-neighbor | tee "$EVIDENCE/recover-bgp.txt" || fail 'BGP recovery'
wait_for 'R1 returns to its direct eBGP primary path' primary_path
pass 'BGP adjacency failure and recovery'

"$LAB" incident ospf-adjacency
wait_for 'the selected OSPF adjacency leaves Full' ospf_absent
"$LAB" recover ospf-adjacency | tee "$EVIDENCE/recover-ospf.txt" || fail 'OSPF recovery'
pass 'OSPF adjacency failure and recovery'

"$LAB" incident route-withdrawal
wait_for 'withdrawn endpoint prefix disappears from R1' route_absent
if node client-a ping -c 2 -W 2 10.20.40.10 >"$EVIDENCE/withdrawal-loss.txt" 2>&1; then fail 'traffic succeeded after endpoint prefix withdrawal'; fi
"$LAB" recover route-withdrawal | tee "$EVIDENCE/recover-withdrawal.txt" || fail 'route reannouncement'
pass 'route withdrawal and reannouncement'

"$LAB" incident link-failure
node r1 ip -brief link | tee -a "$EVIDENCE/observations.txt"
wait_for 'forwarding survives primary inter-AS link failure' end_to_end
must_contain '10\.0\.12\.2' 'R1 forwards through the alternate OSPF/iBGP path' frr r1 'show ip route 10.20.40.0/24'
"$LAB" recover link-failure | tee "$EVIDENCE/recover-link.txt" || fail 'link restoration'
wait_for 'primary link recovery restores direct eBGP path' primary_path
pass 'link failure, alternate path and recovery'

"$LAB" incident policy-rejection
must_contain '198\.51\.100\.0/24' 'restricted prefix is originated at R3' frr r3 'show ip bgp ipv4 unicast'
must_not_contain 'Known via "bgp"' 'policy rejects restricted prefix on R1' frr r1 'show ip route 198.51.100.0/24'
must_not_contain 'Known via "bgp"' 'policy rejects restricted prefix on R2' frr r2 'show ip route 198.51.100.0/24'
"$LAB" recover policy-rejection >/dev/null
pass 'routing policy rejection'

"$LAB" incident reachability-loss
if node client-a ping -c 2 -W 2 10.20.40.10 >"$EVIDENCE/expected-loss.txt" 2>&1; then fail 'blackhole incident unexpectedly forwarded traffic'; fi
pass 'controlled route blackhole causes observed endpoint loss'
"$LAB" recover reachability-loss | tee "$EVIDENCE/recover-reachability.txt" || fail 'reachability recovery'
pass 'reachability loss and recovery'

# Prove that an unavailable device makes the external script fail explicitly.
docker stop clab-routing-lab-r1 >/dev/null || fail 'could not stop the owned R1 test container'
if python3 examples/python/inspect.py >"$EVIDENCE/inaccessible-router.txt" 2>&1; then
  docker start clab-routing-lab-r1 >/dev/null || true
  fail 'Python integration reported success while R1 was unavailable'
fi
grep -Eq 'Docker command failed for node r1|No such container|is not running|unavailable' "$EVIDENCE/inaccessible-router.txt" || fail 'Python integration failure was not explicit'
pass 'Python integration fails explicitly for inaccessible R1'
"$LAB" reset | tee "$EVIDENCE/recover-router.txt" || fail 'full lab reset after R1 outage'
pass 'R1 outage recovery by baseline reset'

"$LAB" evidence
printf 'Evidence directory: %s\n' "$EVIDENCE"
printf 'PASS count: %s\n' "$(grep -c '^PASS:' "$EVIDENCE/results.txt")"

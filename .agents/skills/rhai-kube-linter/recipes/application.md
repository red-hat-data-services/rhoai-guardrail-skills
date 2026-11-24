# Application repository recipe

**Load this recipe when** the lint targets are plain application workloads —
Deployments, StatefulSets, DaemonSets, Jobs, CronJobs, Services. Compose
with the Helm and/or Kustomize format recipe. Controller targets are
assessed by the operator recipes instead: if the repository ships a
controller managing custom resources, load the operator (or
module-operator) recipe for those targets. A mixed repository loads both —
this recipe for its application workloads, the operator recipe for its
controller.

## Check selection from actual workloads

- Start from the baseline container-security, identity, network, reliability,
  and image checks; enable each only where the workload kind can carry the
  field (see semantics below) and the manifests show it matters.
- Extra candidates with evidence: `liveness-port`/`readiness-port` when probes
  and container ports are both declared; `job-ttl-seconds-after-finished` for
  Jobs without a TTL; `duplicate-env-var`; `dnsconfig-options` when
  `dnsConfig` is set; `priority-class-name` for latency-sensitive workloads;
  `minimum-three-replicas`/`no-anti-affinity` for HA-class services the
  repository actually intends to be highly available.

## Precise check semantics — classify, don't exempt generically

Each of these produces findings that look like defects but need kind- or
context-aware classification. Use the observed finding plus the manifest as
evidence; propose narrow exceptions only with justification:

- **Jobs and CronJobs:** liveness/readiness probes are meaningless for
  one-shot pods. If the probe checks fire on Job-creating objects, classify as
  a check-semantics case and propose a narrowly scoped exception for those
  objects — or omit the probe checks only if the repository has no long-running
  workloads at all. Resource requirements still apply to Job containers.
- **Init containers:** resource-requirement and security checks evaluate every
  container including init containers. A missing limit on an init container is
  still an observed issue — init containers run with the pod's priority.
- **Platform-assigned identity:** if `serviceAccountName` is unset, the
  manifest runs as the namespace default account — report it (do not edit
  manifests); declaring the intended account explicitly is the fix the team
  should consider. Distinguish the unset field from the admitted identity:
  when repository or platform evidence shows an admission webhook assigns a
  dedicated service account, record that mutation as an external dependency
  and classify the effective identity from that evidence instead of
  reporting namespace-default use. Without such evidence, the
  default-account finding stands.
- **Intended exposure:** `exposed-services` on a NodePort/LoadBalancer may be
  deliberate (e.g. an ingress controller). Classify as expected requirement
  only with evidence of intent from the repository's own docs/configuration;
  otherwise it stays an observed issue.
- **Writable volumes:** `writable-host-mount` concerns hostPath mounts;
  writable `emptyDir`/PVCs are normal. Read the finding's object and volume
  name before classifying.
- **External resources:** `non-existent-service-account` on an account
  created by another component (chart dependency, platform, another team's
  manifest) is a rendering-context observation — state the assumption that the
  account exists at install time, and mark the dependency in the report.

## Handoff

Map every observation to a check decision or exception scope with concise
manifest evidence, classify findings per the report template, and route
onboarding through the shared entry-point contract.

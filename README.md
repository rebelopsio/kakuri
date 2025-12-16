This repository contains a proof-of-concept “secure runtime orchestrator” that uses a Zig node agent and Edera to run workloads inside strongly isolated zones, without requiring a full Kubernetes cluster.[1][2]

## Overview

The goal of this project is to explore what comes *after* “Kubernetes everywhere” by separating the **control-plane API** from the **runtime isolation** mechanism. Instead of assuming “a workload is a pod of containers on a shared kernel,” this PoC treats a workload as an *isolated execution unit* that can be scheduled onto an Edera zone.[2][3][1]

In this initial iteration:

- The **control plane** exposes a minimal API to submit `Workload` objects and query their status.  
- A **Zig node agent** runs on each worker node and is responsible for turning a `Workload` into an Edera‑backed zone + container via Edera’s CRI‑compatible runtime.[4][5][1]
- **Edera** provides the hardened runtime: a type‑1‑hypervisor‑backed “zone” for each workload, giving VM‑style isolation while keeping container workflows.[3][6][1]

This design keeps the useful pieces of the Kubernetes model (declarative spec, reconciliation, runtime classes) while allowing much stronger security guarantees at the runtime layer.

## Architecture

The PoC architecture consists of three main parts:

1. **Control Plane (CP)**  
   A small service (can be Go or Zig in early versions) that:

   - Accepts new workloads via a REST or simple RPC interface.  
   - Performs basic validation (only `runtime_class = "edera-zone"` for now).  
   - Selects a target node (single node in the PoC).  
   - Sends a `StartWorkload` request to the node’s agent over TCP.  
   - Exposes a `GET /workloads/:id` to fetch status by proxying to the agent.

2. **Zig Node Agent (NA)**  
   A long‑running Zig daemon on each node that:

   - Listens on a TCP port for control-plane RPCs.  
   - Maintains an in‑memory registry mapping `Workload.id` → Edera runtime handles and status.  
   - On `StartWorkload`, calls Edera’s CRI endpoint to create a sandbox (“zone”) and container.  
   - On `GetStatus`, queries Edera for container/pod status and translates it into a simple state model (`Pending`, `Running`, `Failed`, `Succeeded`).

3. **Edera Runtime**  
   Edera is responsible for:

   - Providing the **zone** abstraction: each zone is a VM‑like environment hosting a pod or container with its own kernel, designed as “Goldilocks isolation” between heavy VMs and shared‑kernel containers.[6][1][3]
   - Exposing a **CRI‑compatible** container runtime so that kubelet (or, in this case, a custom agent) can start pods/containers via standard CRI calls.[5][1][4]
   - Implementing hardened runtime and isolation guarantees, with tooling such as “Am I Isolated?” to assess container isolation posture.[7][8][9]

The PoC deliberately **does not** run Kubernetes; instead, it talks to Edera directly at the CRI layer to prove that the orchestration logic can be decoupled from Kubernetes while still benefiting from Edera’s security model.[10][1][2]

## Data Model

### Workload

A `Workload` is the core API object for this PoC. It represents a single containerized application that should run inside an Edera zone.

Example JSON:

```json
{
  "id": "wl-123",
  "image": "ghcr.io/example/secure-app:1.0",
  "runtime_class": "edera-zone",
  "memory_mb": 512,
  "cpu_millicores": 500
}
```

Fields:

- `id`: Unique string identifier for the workload.  
- `image`: OCI image reference for the container.  
- `runtime_class`: For this PoC, must be `"edera-zone"`; in the future, this can be extended to `"kata"`, `"gvisor"`, `"native"`, etc., and scheduled accordingly.[1][5]
- `memory_mb`: Memory limit for the container inside the zone.  
- `cpu_millicores`: CPU limit, if supported by the underlying runtime.

### Internal Types

On the node agent, this maps to:

- `Workload` (incoming spec).  
- `EderaHandle` (internal): something like `{ pod_sandbox_id, container_id }`.  
- `WorkloadState`: enum (`Pending`, `Running`, `Failed`, `Succeeded`).

## RPC Protocol (Control Plane ⇄ Node Agent)

The protocol between the control plane and node agents is intentionally simple: line‑delimited JSON over TCP.

Messages:

```json
// From CP to NA: start a new workload
{ "type": "StartWorkload", "workload": { ...Workload... } }

// From CP to NA: ask for status
{ "type": "GetStatus", "id": "wl-123" }

// From NA to CP: status response
{ "type": "Status", "id": "wl-123", "state": "Running" }
```

This can later be upgraded to a more structured RPC (e.g., framed binary, gRPC, QUIC), but JSON keeps the PoC easy to debug with netcat or `socat`.

## Zig Node Agent Layout

A suggested Zig module layout:

- `src/main.zig`  
  - Sets up allocator, parses config (e.g., node ID, Edera socket path).  
  - Binds a TCP listener (e.g., `0.0.0.0:9000`) and accepts connections.  
  - For each connection, reads one or more messages and dispatches to handlers.

- `src/rpc.zig`  
  - Defines in‑memory structs for `StartWorkload`, `GetStatus`, `StatusResponse`.  
  - Implements minimal JSON encode/decode helpers.

- `src/workload.zig`  
  - Holds an in‑memory map from `Workload.id` to `{ handle: EderaHandle, state: WorkloadState }`.  
  - Provides helper functions `register`, `update_state`, `get_state`.

- `src/edera.zig`  
  - Encapsulates all Edera/CRI integration.  
  - Exports functions:
    - `pub fn startZoneAndContainer(w: Workload) !EderaHandle`  
    - `pub fn getStatus(handle: EderaHandle) !WorkloadState`

The node agent uses **blocking I/O** for the PoC to keep concurrency simple; once the basic path works, async I/O or a small reactor can be added.

## Edera Integration Strategy

Edera provides a CRI‑compatible runtime, typically via a Unix domain socket that kubelet would talk to when `runtimeClassName` selects Edera.[11][4][1]

The PoC uses this same CRI endpoint directly:

- Connect to Edera’s CRI socket (for example, something like `unix:///var/lib/edera/protect/cri.socket`; the exact path is installation‑specific).[4][11]
- Implement (or reuse) enough of the CRI v1 API to:
  - Call `RunPodSandbox` with a config that corresponds to a single‑pod zone.  
  - Call `CreateContainer` and `StartContainer` with the `image`, resources, and basic metadata.  
  - Call `ContainerStatus` and optionally `PodSandboxStatus` to track lifecycle.[5][1][4]

For the first iteration, there are two workable options:

- **Thin CRI client in another language**:  
  Wrap Edera’s CRI with a tiny local sidecar written in Go or Rust that exposes a simpler Unix socket or HTTP API, and call that from Zig. This avoids writing full gRPC + protobuf handling in Zig immediately.

- **All‑Zig CRI client** (longer term):  
  Define the needed CRI request/response types as Zig structs using the official proto definitions as reference, then speak gRPC over Unix sockets from Zig. This aligns strongly with the project’s goal of a Zig‑first stack, but is more work up front.[12][5]

The important point is that **the orchestrator never needs to know how Edera implements zones internally**; it just relies on the contract: “if I run a pod/container through Edera’s CRI, I get hardened isolation backed by a type‑1 hypervisor.”[3][6][1]

## Minimal Control Plane

The control plane is intentionally minimal for this PoC:

- **Endpoints** (if implemented as HTTP):

  - `POST /workloads`  
    - Body: `Workload` JSON.  
    - Behavior: validate, generate or confirm `id`, select node, send `StartWorkload` RPC, return created spec.

  - `GET /workloads/:id`  
    - Behavior: send `GetStatus` to the node agent that owns the workload, return current state.

- **Scheduling**  
  - First version: hard‑code a single Edera‑enabled node.  
  - Later: basic capacity tracking (how many workloads per node, memory/CPU accounting).

The control plane can initially be written in Go (faster iteration, batteries‑included HTTP) and later reimplemented in Zig once the overall design feels right.

## PoC Workflow

1. **Set up an Edera node**

   - Install Edera following its docs and ensure the CRI‑compatible runtime is running on the worker node.[13][2]
   - Note the path to the CRI socket and verify it responds (e.g., using `crictl` pointing at Edera).[4][5]

2. **Run the Zig node agent**

   - Build and start the Zig agent on the same node, configured with:
     - Node ID (e.g., `node-1`).  
     - Edera CRI socket path.  
     - Listen address for control-plane RPCs (e.g., `0.0.0.0:9000`).

3. **Run the control plane**

   - Start the control plane service with a config listing `node-1` and its agent address.  
   - Ensure it can open a TCP connection to `node-1:9000`.

4. **Submit a test workload**

   - `POST /workloads` (or equivalent CLI) with a simple container image that can run in an Edera zone (e.g., a small static binary).[2][13]
   - Control plane forwards `StartWorkload` to the node agent.

5. **Observe Edera behavior**

   - Verify that Edera creates a new zone and container for this workload.  
   - Use Edera’s tooling (logs, CLI, or UI) to confirm the workload is running with the expected isolation profile.[10][2][3]

6. **Query status**

   - Call `GET /workloads/:id` to retrieve `Running`/`Failed`/`Succeeded` based on Edera’s container status.  
   - Optionally, stop or delete the workload and ensure the agent/CP keep state consistent.

## Future Directions

This PoC sets the foundation for a more ambitious platform:

- **Multiple runtime classes**: Introduce `runtime_class` values for Edera, Kata, gVisor, and native containerd, and let the scheduler pick based on a higher‑level `SecurityProfile` object.[14][15][1]
- **Policy‑driven isolation**: Add objects like `SecurityProfile` or `IsolationPolicy` that describe trust levels (`untrusted`, `multi_tenant`, `internal`) and map them to runtime classes.[16][7][1]
- **“Am I isolated?” integration**: Use Edera’s “Am I Isolated?” tooling to periodically assess workloads and surface isolation scores back into the control plane.[8][9][7]
- **Better APIs**: Replace the ad‑hoc JSON RPC with a proper typed API (e.g., protobuf or Zig‑native schemas with comptime‑generated codecs).

For now, this repository focuses on standing up the **first vertical slice**: submit a `Workload`, have a Zig agent talk to Edera, and see a container running inside a hardened zone with observable status.

[1](https://arxiv.org/html/2501.04580v1)
[2](https://docs.edera.dev/overview/)
[3](https://docs.edera.dev/technical-overview/concepts/zone/)
[4](https://docs.edera.dev/reference/release-notes/v1.3.0/)
[5](https://kubernetes.io/docs/concepts/containers/cri/)
[6](https://edera.dev/stories/what-the-f-ck-is-a-zone-secure-container-isolation-with-edera)
[7](https://cloudnativenow.com/topics/cloudnativesecurity/ederas-big-container-security-question-am-i-isolated/)
[8](https://www.devopsdigest.com/edera-releases-am-i-isolated)
[9](https://www.scworld.com/brief/edera-launches-open-source-tool-for-container-runtime-security)
[10](https://docs.edera.dev/technical-overview/architecture/overview/)
[11](https://docs.edera.dev/get-support/troubleshooting/disable/)
[12](https://ziglang.org/documentation/0.13.0/)
[13](https://docs.edera.dev/getting-started/)
[14](https://onidel.com/gvisor-kata-firecracker-2025/)
[15](https://aws.amazon.com/blogs/containers/enhancing-kubernetes-workload-isolation-and-security-using-kata-containers/)
[16](https://www.softwareplaza.com/it-magazine/edera's-approach-to-container-isolation-that-focuses-on-security-and-efficiency)

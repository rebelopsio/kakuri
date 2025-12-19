# Kakuri Learning Roadmap: Building Systems from Scratch

This document outlines the approach for building the kakuri orchestrator while implementing core libraries (JSON, HTTP, TCP) from scratch in Zig.

## Philosophy

This project prioritizes **deep learning over rapid development**. We're building foundational libraries manually to understand systems programming concepts thoroughly, rather than using existing dependencies.

## Core Libraries to Build

### 1. JSON Parser/Serializer
**Purpose:** Everything in this project communicates via JSON  
**Learning Focus:** Parsing, memory allocation, recursive data structures  
**Timeline:** Week 1-2

### 2. Line-Delimited TCP Protocol Handler
**Purpose:** Agent communication protocol  
**Learning Focus:** Socket programming, buffering, network I/O  
**Timeline:** Week 2-3

### 3. HTTP/1.1 Server
**Purpose:** Control plane API  
**Learning Focus:** Protocol implementation, request/response handling  
**Timeline:** Week 3-5

### 4. (Optional) HTTP Client
**Purpose:** Understanding both sides of HTTP  
**Learning Focus:** Client-side connection management  
**Timeline:** Week 5-6

### 5. (Future) gRPC/Protobuf Client
**Purpose:** Direct Edera CRI integration  
**Learning Focus:** Binary protocols, HTTP/2, Unix sockets  
**Timeline:** Week 7+

---

## Project Phases

### Phase 1: JSON Foundation (Week 1-2)

**Goal:** Working JSON parser and serializer for project needs

#### Deliverables
1. Parse JSON text → Zig values
2. Serialize Zig structs → JSON text  
3. Handle project-specific types (Workload, RPC messages)

#### First Milestone
Successfully parse this JSON into a `Workload` struct:
```json
{
  "id": "wl-123",
  "image": "nginx:latest",
  "runtime_class": "edera-zone",
  "memory_mb": 512,
  "cpu_millicores": 500
}
```

#### Key Decisions to Make

**1. JSON Representation**
How to represent parsed JSON before mapping to structs?

Option A: Tagged union (flexible)
```zig
const Value = union(enum) {
    null,
    bool: bool,
    number: f64,
    string: []const u8,
    array: []Value,
    object: std.StringHashMap(Value),
};
```

Option B: Direct to target type (simpler)
```zig
// Parse directly to Workload struct
// Less flexible but fewer allocations
```

**2. Parsing Strategy**

Option A: Two-phase (tokenize then parse)
```zig
const Token = union(enum) {
    brace_open,
    brace_close,
    bracket_open,
    bracket_close,
    colon,
    comma,
    string: []const u8,
    number: f64,
    true,
    false,
    null,
};
```

Option B: Recursive descent directly
```zig
// Parse JSON grammar directly without tokenization
// State machine approach
```

**3. Memory Allocation Strategy**
```zig
// Questions to answer:
// - All parsed data from one arena?
// - Caller provides allocator?
// - How long does parsed data live?
// - Who owns string memory?
```

#### Implementation Approach

**Step 1:** Parse simple flat objects only
```json
{"key": "value", "number": 123}
```

**Step 2:** Expand to nested objects
```json
{"outer": {"inner": "value"}}
```

**Step 3:** Add array support
```json
{"items": [1, 2, 3]}
```

**Step 4:** Handle edge cases
- Escape sequences (`\"`, `\n`, `\t`)
- Number formats (int vs float, scientific notation)
- Unicode (basic support)

#### Learning Artifacts
- Blog post: "Building a JSON Parser in Zig"
- Document your allocator decisions
- Performance notes (how fast is it?)

#### Key Questions to Research
1. How does `std.json` work internally? (read the source for ideas)
2. What are JSON's edge cases? (NaN, infinity, escape sequences)
3. How do other languages handle JSON → struct mapping?
4. What's the difference between copying strings vs keeping references?

---

### Phase 2: Agent TCP Server (Week 2-3)

**Goal:** Agent that accepts connections and handles line-delimited JSON requests

#### Deliverables
1. Listen on port 9000
2. Accept incoming connections
3. Read line-delimited JSON using your parser
4. Dispatch to handlers (stubs initially OK)
5. Send JSON responses using your serializer

#### Milestone Test
Using `netcat`, send a request:
```bash
echo '{"type":"GetStatus","id":"wl-123"}' | nc localhost 9000
```

Receive response:
```json
{"type":"Status","id":"wl-123","state":"Pending"}
```

#### What You'll Learn
- Raw socket programming (`std.posix` APIs)
- The `socket()`, `bind()`, `listen()`, `accept()` flow
- Buffered reading (one `read()` ≠ one message)
- Connection lifecycle management
- Error handling for network I/O

#### Key Challenge: Partial Reads

You cannot assume one `read()` call returns a complete message:

```zig
// You might receive data like this across multiple reads:
// Read 1: "{\n"
// Read 2: "\"type\": \"Start"
// Read 3: "Workload\"}\n"
// 
// Must buffer until you have a complete line (up to \n)
```

#### Suggested Structure

```zig
// src/tcp/server.zig
pub const Server = struct {
    allocator: Allocator,
    socket: std.posix.socket_t,
    address: std.net.Address,
    
    pub fn init(allocator: Allocator, addr: []const u8, port: u16) !Server {
        // Create socket
        // Bind to address
        // Listen for connections
    }
    
    pub fn accept(self: *Server) !Connection {
        // Accept next connection
    }
    
    pub fn deinit(self: *Server) void {
        // Close socket
    }
};

pub const Connection = struct {
    socket: std.posix.socket_t,
    
    pub fn reader(self: Connection) Reader {
        // Return a reader for this connection
    }
    
    pub fn writer(self: Connection) Writer {
        // Return a writer for this connection
    }
    
    pub fn close(self: Connection) void {
        // Close connection
    }
};

// src/tcp/buffered_reader.zig
pub const LineReader = struct {
    buffer: [4096]u8,
    buffer_len: usize,
    stream: std.net.Stream,
    
    pub fn readLine(self: *LineReader, allocator: Allocator) !?[]u8 {
        // Read until \n, handling partial reads
        // Return owned string (caller must free)
    }
};
```

#### Implementation Steps

**Step 1:** Basic socket setup
- Create socket
- Bind to address
- Listen
- Accept one connection
- Read some bytes
- Close

**Step 2:** Line-delimited reading
- Implement buffered line reader
- Handle partial reads
- Handle multiple lines in one buffer

**Step 3:** Request/response loop
- Read line → parse JSON → handle → serialize → write response
- Handle connection errors gracefully

**Step 4:** Multiple connections
- Accept → handle → accept next (sequential for now)

#### Learning Artifacts
- Blog post: "Building a TCP Server in Zig"
- Document buffering strategy
- Network error handling patterns

---

### Phase 3: Workload Registry (Week 3)

**Goal:** In-memory state management for workloads

#### Deliverables
1. HashMap-based registry (id → state)
2. Register/update/query operations
3. Proper memory management
4. Thread-safety considerations (single-threaded OK initially)

#### Milestone
Agent can:
- Accept `StartWorkload` → store in registry → respond with confirmation
- Accept `GetStatus` → look up in registry → respond with current state
- Maintain state across multiple requests

#### Types to Implement

```zig
// src/workload.zig

pub const WorkloadState = enum {
    pending,
    running,
    failed,
    succeeded,
};

pub const Workload = struct {
    id: []const u8,
    image: []const u8,
    runtime_class: []const u8,
    memory_mb: u32,
    cpu_millicores: u32,
};

pub const EderaHandle = struct {
    pod_sandbox_id: []const u8,
    container_id: []const u8,
};

pub const WorkloadEntry = struct {
    workload: Workload,
    state: WorkloadState,
    handle: ?EderaHandle, // null until started with Edera
};

pub const WorkloadRegistry = struct {
    allocator: Allocator,
    entries: std.StringHashMap(WorkloadEntry),
    
    pub fn init(allocator: Allocator) WorkloadRegistry {
        // Initialize empty registry
    }
    
    pub fn register(self: *WorkloadRegistry, workload: Workload) !void {
        // Add workload in pending state
        // Must copy workload data (it owns the memory)
    }
    
    pub fn updateState(self: *WorkloadRegistry, id: []const u8, state: WorkloadState) !void {
        // Update workload state
    }
    
    pub fn setHandle(self: *WorkloadRegistry, id: []const u8, handle: EderaHandle) !void {
        // Store Edera handle for workload
    }
    
    pub fn get(self: *WorkloadRegistry, id: []const u8) ?*WorkloadEntry {
        // Look up workload by id
    }
    
    pub fn deinit(self: *WorkloadRegistry) void {
        // Free all stored data
    }
};
```

#### Key Decisions

**1. Memory Ownership**
- Does the registry own workload strings (id, image)?
- When do you free them?
- Should you use an arena for all registry data?

**2. String Keys**
- `std.StringHashMap` requires owned strings as keys
- Do you copy the id when registering?
- Consider using `std.StringArrayHashMap` for iteration

**3. Lifecycle**
- When are workloads removed from registry?
- Support for deletion/cleanup?
- Limit on number of workloads?

#### Implementation Steps

**Step 1:** Basic HashMap operations
- Create registry
- Add entry
- Look up entry
- Verify memory management (use GPA with leak detection)

**Step 2:** Integration with agent
- Wire up `StartWorkload` handler to registry
- Wire up `GetStatus` handler to registry
- Handle errors (workload not found, duplicate id)

**Step 3:** State transitions
- Implement state machine (pending → running → succeeded/failed)
- Validate state transitions
- Handle edge cases

#### Learning Focus
- HashMap usage and allocators
- Lifetime management
- When to copy vs reference data
- Error handling strategies

---

### Phase 4: HTTP Server for Control Plane (Week 4-5)

**Goal:** Minimal HTTP/1.1 server for control plane API

#### Deliverables
1. Parse HTTP requests (method, path, headers, body)
2. Route by method + path pattern
3. Read JSON request bodies
4. Write JSON responses with proper headers
5. Support Keep-Alive connections

#### Milestone
```bash
# Create workload
curl -X POST http://localhost:8080/workloads \
  -H "Content-Type: application/json" \
  -d '{"id":"wl-123","image":"nginx:latest","runtime_class":"edera-zone","memory_mb":512,"cpu_millicores":500}'

# Returns: 201 Created with workload JSON

# Get workload status
curl http://localhost:8080/workloads/wl-123

# Returns: 200 OK with status JSON
```

#### What You'll Learn
- HTTP/1.1 protocol specification
- Request/response formatting
- Header parsing
- Content-Length and message framing
- Status codes and their meanings

#### MVP Scope

**Must Support:**
- Methods: GET, POST
- Parse: request line, headers, body
- Content-Length for body framing
- Response: status line, headers, body
- Connection: Keep-Alive (reuse connections)

**Can Skip Initially:**
- Other methods (PUT, DELETE, PATCH)
- Transfer-Encoding: chunked
- Range requests
- Compression (gzip)
- HTTPS/TLS
- Most headers (focus on Content-Length, Content-Type)
- Query parameters (add when needed)

#### HTTP Request Format

```
GET /workloads/wl-123 HTTP/1.1\r\n
Host: localhost:8080\r\n
User-Agent: curl/7.64.1\r\n
Accept: */*\r\n
\r\n
```

**Components:**
1. Request line: `METHOD PATH VERSION\r\n`
2. Headers: `Key: Value\r\n` (repeated)
3. Blank line: `\r\n`
4. Body: (length from Content-Length header)

#### HTTP Response Format

```
HTTP/1.1 200 OK\r\n
Content-Type: application/json\r\n
Content-Length: 123\r\n
Connection: keep-alive\r\n
\r\n
{"id":"wl-123","state":"Running"}
```

#### Suggested Structure

```zig
// src/http/server.zig
pub const Server = struct {
    allocator: Allocator,
    tcp_server: tcp.Server,
    router: Router,
    
    pub fn init(allocator: Allocator, addr: []const u8, port: u16) !Server {
        // Set up TCP server
    }
    
    pub fn listen(self: *Server) !void {
        while (true) {
            const conn = try self.tcp_server.accept();
            // Handle connection (sequential for now)
            self.handleConnection(conn) catch |err| {
                std.log.err("Error handling connection: {}", .{err});
            };
            conn.close();
        }
    }
    
    fn handleConnection(self: *Server, conn: tcp.Connection) !void {
        // Can handle multiple requests per connection (keep-alive)
        while (true) {
            const request = Request.parse(self.allocator, conn.reader()) catch |err| {
                if (err == error.ConnectionClosed) break;
                return err;
            };
            defer request.deinit();
            
            const response = try self.router.route(request);
            defer response.deinit();
            
            try response.write(conn.writer());
        }
    }
};

// src/http/request.zig
pub const Method = enum {
    GET,
    POST,
    // Add others as needed
};

pub const Request = struct {
    allocator: Allocator,
    method: Method,
    path: []const u8,
    version: []const u8,
    headers: Headers,
    body: []const u8,
    
    pub fn parse(allocator: Allocator, reader: anytype) !Request {
        // Parse request line
        // Parse headers
        // Read body based on Content-Length
    }
    
    pub fn deinit(self: *Request) void {
        // Free allocated memory
    }
};

// src/http/response.zig
pub const StatusCode = enum(u16) {
    ok = 200,
    created = 201,
    bad_request = 400,
    not_found = 404,
    internal_server_error = 500,
    // Add others as needed
    
    pub fn reasonPhrase(self: StatusCode) []const u8 {
        return switch (self) {
            .ok => "OK",
            .created => "Created",
            .bad_request => "Bad Request",
            .not_found => "Not Found",
            .internal_server_error => "Internal Server Error",
        };
    }
};

pub const Response = struct {
    allocator: Allocator,
    status: StatusCode,
    headers: Headers,
    body: []const u8,
    
    pub fn init(allocator: Allocator, status: StatusCode) Response {
        // Create response with status
    }
    
    pub fn write(self: Response, writer: anytype) !void {
        // Write status line
        try writer.print("HTTP/1.1 {} {}\r\n", .{
            @intFromEnum(self.status),
            self.status.reasonPhrase(),
        });
        
        // Write headers
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            try writer.print("{s}: {s}\r\n", .{entry.key_ptr.*, entry.value_ptr.*});
        }
        
        // Blank line
        try writer.writeAll("\r\n");
        
        // Body
        try writer.writeAll(self.body);
    }
    
    pub fn deinit(self: *Response) void {
        // Free memory
    }
};

// src/http/headers.zig
pub const Headers = struct {
    map: std.StringHashMap([]const u8),
    
    pub fn init(allocator: Allocator) Headers {
        return .{ .map = std.StringHashMap([]const u8).init(allocator) };
    }
    
    pub fn get(self: Headers, key: []const u8) ?[]const u8 {
        // Case-insensitive lookup
    }
    
    pub fn set(self: *Headers, key: []const u8, value: []const u8) !void {
        // Store header (must copy strings)
    }
    
    pub fn deinit(self: *Headers) void {
        // Free map and strings
    }
};

// src/http/router.zig
pub const Handler = *const fn(Request) anyerror!Response;

pub const Route = struct {
    method: Method,
    pattern: []const u8, // e.g., "/workloads/:id"
    handler: Handler,
};

pub const Router = struct {
    routes: std.ArrayList(Route),
    
    pub fn add(self: *Router, method: Method, pattern: []const u8, handler: Handler) !void {
        // Add route
    }
    
    pub fn route(self: Router, request: Request) !Response {
        // Find matching route
        // Extract path parameters (e.g., :id)
        // Call handler
    }
};
```

#### Implementation Steps

**Step 1: Request Line Parsing**
```zig
// Parse: "GET /workloads/wl-123 HTTP/1.1\r\n"
// Extract: method, path, version
// Handle malformed requests
```

**Step 2: Header Parsing**
```zig
// Parse: "Header-Name: Header Value\r\n"
// Repeat until blank line: "\r\n"
// Store in case-insensitive map
```

**Step 3: Body Reading**
```zig
// Check for Content-Length header
// Read exactly that many bytes
// Handle missing/invalid Content-Length
```

**Step 4: Response Writing**
```zig
// Format status line
// Write headers
// Write body
// Ensure \r\n separators
```

**Step 5: Routing**
```zig
// Match request to handler
// Extract path parameters (/workloads/:id)
// Return 404 if no match
```

**Step 6: Keep-Alive**
```zig
// Don't close connection after each response
// Loop reading requests until connection closed
// Handle Connection: close header
```

#### Learning Artifacts
- Blog post: "Implementing HTTP/1.1 in Zig"
- Wire format examples with hex dumps
- State machine diagram for request parsing
- Performance comparison with existing servers

#### Common Pitfalls
1. **Forgetting `\r\n`**: HTTP requires CRLF, not just `\n`
2. **Case sensitivity**: Header names are case-insensitive
3. **Incomplete reads**: Body might come across multiple `read()` calls
4. **Memory leaks**: Must free all allocated request/response data
5. **Keep-Alive**: Don't close connection after first response

---

### Phase 5: Control Plane → Agent Communication (Week 6)

**Goal:** Control plane forwards requests to agent and returns results

#### Deliverables
1. CP opens TCP connection to agent
2. Sends StartWorkload request in line-delimited JSON
3. Reads response
4. Returns to HTTP client
5. Error handling when agent unreachable

#### Milestone: End-to-End Flow
```
HTTP Client
  → POST /workloads (HTTP)
    → Control Plane
      → StartWorkload (TCP + JSON)
        → Agent
          → Registry
          → (Edera stub for now)
        ← Status Response
      ← TCP Response
    ← HTTP Response (201 Created)
  ← JSON Body
```

#### What You'll Learn
- Multiple I/O streams simultaneously
- Error propagation across network boundaries
- Timeout handling
- Connection pooling considerations

#### Suggested Structure

```zig
// src/control_plane/agent_client.zig
pub const AgentClient = struct {
    allocator: Allocator,
    agent_address: std.net.Address,
    
    pub fn init(allocator: Allocator, addr: []const u8, port: u16) !AgentClient {
        // Parse address
    }
    
    pub fn startWorkload(self: AgentClient, workload: Workload) !void {
        // Connect to agent
        const conn = try std.net.tcpConnectToAddress(self.agent_address);
        defer conn.close();
        
        // Send StartWorkload message
        const msg = rpc.StartWorkload{ .workload = workload };
        const json = try json_serializer.serialize(self.allocator, msg);
        defer self.allocator.free(json);
        
        try conn.writeAll(json);
        try conn.writeAll("\n");
        
        // Read response (with timeout?)
        // Parse and validate response
    }
    
    pub fn getStatus(self: AgentClient, id: []const u8) !WorkloadState {
        // Similar to startWorkload
        // Send GetStatus message
        // Parse Status response
    }
};
```

#### HTTP Handlers in Control Plane

```zig
// cmd/control-plane/main.zig (or src/control_plane/handlers.zig)

fn handleCreateWorkload(request: http.Request) !http.Response {
    // Parse JSON body to Workload
    const workload = try json_parser.parse(Workload, request.body);
    
    // Validate workload
    if (!std.mem.eql(u8, workload.runtime_class, "edera-zone")) {
        return http.Response.init(.bad_request)
            .withBody("Only edera-zone runtime class supported");
    }
    
    // Forward to agent
    try agent_client.startWorkload(workload);
    
    // Return success
    var response = http.Response.init(.created);
    try response.headers.set("Content-Type", "application/json");
    const body = try json_serializer.serialize(allocator, workload);
    response.body = body;
    return response;
}

fn handleGetWorkload(request: http.Request) !http.Response {
    // Extract :id from path
    const id = extractPathParam(request.path, "id");
    
    // Query agent
    const state = try agent_client.getStatus(id);
    
    // Return status
    const status_response = .{ .id = id, .state = state };
    var response = http.Response.init(.ok);
    try response.headers.set("Content-Type", "application/json");
    response.body = try json_serializer.serialize(allocator, status_response);
    return response;
}
```

#### Error Handling Strategy

```zig
// Control plane must handle:
// 1. Invalid HTTP requests (400 Bad Request)
// 2. Agent unreachable (503 Service Unavailable)
// 3. Agent errors (500 Internal Server Error)
// 4. Workload not found (404 Not Found)

fn handleError(err: anyerror) http.Response {
    return switch (err) {
        error.ConnectionRefused => http.Response.init(.service_unavailable)
            .withBody("Agent unreachable"),
        error.WorkloadNotFound => http.Response.init(.not_found)
            .withBody("Workload not found"),
        error.InvalidJson => http.Response.init(.bad_request)
            .withBody("Invalid JSON"),
        else => http.Response.init(.internal_server_error)
            .withBody("Internal error"),
    };
}
```

#### Testing the Flow

**Terminal 1: Start Agent**
```bash
zig build run-agent
# Agent listening on 0.0.0.0:9000
```

**Terminal 2: Start Control Plane**
```bash
zig build run-control-plane
# Control plane listening on 0.0.0.0:8080
# Connected to agent at localhost:9000
```

**Terminal 3: Send Request**
```bash
curl -X POST http://localhost:8080/workloads \
  -H "Content-Type: application/json" \
  -d '{
    "id": "wl-test-123",
    "image": "nginx:latest",
    "runtime_class": "edera-zone",
    "memory_mb": 512,
    "cpu_millicores": 500
  }'
```

**Verify:**
- Agent logs show received StartWorkload request
- Agent adds to registry
- Control plane receives response
- HTTP client receives 201 Created

---

### Phase 6: Edera Integration (Week 7+)

**Goal:** Actually run workloads in Edera zones

At this point, you have a working orchestrator with mock workload execution. Now integrate real Edera.

#### Two Paths

##### Path A: Go Sidecar (Recommended First)

**Why:** Validates Edera behavior while keeping Zig learning separate

**Architecture:**
```
Agent (Zig)
  → HTTP/Unix Socket
    → Go Sidecar
      → gRPC over Unix Socket
        → Edera CRI Runtime
```

**Go Sidecar Responsibilities:**
- Listen on HTTP or Unix socket
- Accept simplified JSON requests:
  - `POST /zones` → create zone + container
  - `GET /zones/:id` → get status
  - `DELETE /zones/:id` → stop and remove
- Translate to CRI gRPC calls:
  - `RunPodSandbox`
  - `CreateContainer`
  - `StartContainer`
  - `ContainerStatus`
- Return simplified JSON responses

**Implementation:**
```go
// sidecar/main.go
package main

import (
    "context"
    "encoding/json"
    "net/http"
    
    runtime "k8s.io/cri-api/pkg/apis/runtime/v1"
    "google.golang.org/grpc"
)

type StartZoneRequest struct {
    ID           string `json:"id"`
    Image        string `json:"image"`
    MemoryMB     int    `json:"memory_mb"`
    CPUMillicores int   `json:"cpu_millicores"`
}

type ZoneStatus struct {
    ID    string `json:"id"`
    State string `json:"state"` // pending, running, failed, succeeded
}

func main() {
    // Connect to Edera CRI socket
    conn, err := grpc.Dial(
        "unix:///var/lib/edera/protect/cri.socket",
        grpc.WithInsecure(),
    )
    if err != nil {
        log.Fatal(err)
    }
    
    runtimeClient := runtime.NewRuntimeServiceClient(conn)
    imageClient := runtime.NewImageServiceClient(conn)
    
    // HTTP server for agent
    http.HandleFunc("/zones", handleStartZone(runtimeClient, imageClient))
    http.HandleFunc("/zones/", handleGetZoneStatus(runtimeClient))
    
    log.Fatal(http.ListenAndServe(":9001", nil))
}
```

**Agent Integration:**
```zig
// src/edera.zig (now calls Go sidecar)
pub const EderaClient = struct {
    allocator: Allocator,
    sidecar_url: []const u8,
    
    pub fn startZoneAndContainer(self: EderaClient, w: Workload) !EderaHandle {
        // HTTP POST to sidecar
        // Parse response for pod_sandbox_id and container_id
    }
    
    pub fn getStatus(self: EderaClient, handle: EderaHandle) !WorkloadState {
        // HTTP GET to sidecar
        // Parse state
    }
};
```

##### Path B: Direct CRI from Zig (Ambitious)

**Why:** Full Zig stack, deeper learning, more control

**What You'd Need to Build:**

1. **Protobuf Codec**
   - Parse `.proto` files or hand-write message types
   - Encode/decode protobuf wire format
   - Handle field numbering, types, varint encoding

2. **HTTP/2 Client**
   - Connection preface
   - Frame parsing (HEADERS, DATA, SETTINGS)
   - HPACK header compression
   - Stream multiplexing (though you might just use one stream)

3. **gRPC Protocol**
   - Message framing (5-byte length prefix)
   - Trailers handling
   - Status codes

4. **CRI Message Types**
   From `cri-api` proto definitions:
   - `RunPodSandboxRequest/Response`
   - `CreateContainerRequest/Response`
   - `StartContainerRequest/Response`
   - `ContainerStatusRequest/Response`

**This is a significant undertaking** (3-4 weeks alone), but would teach you:
- Binary protocols
- Protocol buffers
- HTTP/2 internals
- gRPC mechanics

**Suggested Structure if Pursuing:**
```zig
// src/grpc/
//   client.zig         - gRPC client over HTTP/2
//   message.zig        - Message framing
//   status.zig         - Status codes
//
// src/protobuf/
//   decoder.zig        - Wire format decoder
//   encoder.zig        - Wire format encoder
//   types.zig          - Common types (varint, etc.)
//
// src/http2/
//   client.zig         - HTTP/2 client
//   frame.zig          - Frame types
//   hpack.zig          - Header compression
//
// src/cri/
//   types.zig          - CRI message definitions
//   runtime.zig        - RuntimeService client
//   image.zig          - ImageService client
```

#### Recommendation

1. **Start with Path A (Go sidecar)** to validate Edera integration
2. Get the full orchestrator working end-to-end
3. **Then** tackle Path B as a learning project if desired
4. Can run both in parallel: sidecar for production, native Zig for learning

---

## Recommended Project Structure

```
kakuri/
├── build.zig
├── build.zig.zon
├── README.md
├── LEARNING_ROADMAP.md          # This document
│
├── cmd/
│   ├── agent/
│   │   └── main.zig             # Agent entry point
│   └── control-plane/
│       └── main.zig             # Control plane entry point
│
├── src/
│   ├── root.zig                 # Project root exports
│   ├── main.zig                 # Shared entry point logic
│   ├── config.zig               # Configuration types
│   ├── workload.zig             # Workload types & registry
│   ├── rpc.zig                  # RPC message types
│   ├── edera.zig                # Edera integration
│   │
│   ├── json/
│   │   ├── parser.zig          # JSON → Zig
│   │   ├── serializer.zig      # Zig → JSON
│   │   ├── types.zig           # JSON value representation
│   │   └── tests.zig           # Unit tests
│   │
│   ├── tcp/
│   │   ├── server.zig          # TCP server
│   │   ├── client.zig          # TCP client
│   │   ├── buffered_reader.zig # Line-delimited reading
│   │   └── tests.zig
│   │
│   ├── http/
│   │   ├── server.zig          # HTTP server
│   │   ├── request.zig         # Request parsing
│   │   ├── response.zig        # Response formatting
│   │   ├── headers.zig         # Header map
│   │   ├── router.zig          # Path routing
│   │   └── tests.zig
│   │
│   └── (future) grpc/
│       ├── client.zig
│       ├── message.zig
│       └── ...
│
├── sidecar/                     # Go sidecar (optional Path A)
│   ├── go.mod
│   ├── main.go
│   └── cri/
│       └── client.go
│
└── docs/
    ├── json-parser.md           # Design decisions
    ├── http-implementation.md   # Wire formats, examples
    └── edera-integration.md     # CRI integration notes
```

---

## Development Workflow

### Iteration Loop with Lima

Your development workflow will look like:

**On macOS Host:**
1. Edit Zig code
2. `zig build`
3. Run control plane locally: `zig build run-control-plane`

**In Lima VM:**
1. `scp` or shared folder with built agent binary
2. Run agent: `./kakuri-agent`
3. Edera is already installed and running

**Test:**
```bash
# From host
curl -X POST http://localhost:8080/workloads -H "Content-Type: application/json" -d '{...}'
```

### Development Tips

1. **Use `GeneralPurposeAllocator` with leak detection during development:**
```zig
var gpa = std.heap.GeneralPurposeAllocator(.{
    .safety = true,        // Extra checks
    .thread_safe = false,  // Single-threaded for now
}){};
defer {
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.log.err("Memory leaked!", .{});
    }
}
```

2. **Write tests as you go:**
```zig
// In each module
test "json parser handles simple object" {
    const allocator = std.testing.allocator;
    const json = "{\"key\": \"value\"}";
    const parsed = try parse(allocator, json);
    defer parsed.deinit();
    
    try std.testing.expectEqualStrings("value", parsed.object.get("key").?.string);
}
```

3. **Log liberally:**
```zig
const log = std.log.scoped(.agent);
log.debug("Received request: {s}", .{request_json});
log.info("Started workload {s}", .{workload.id});
log.err("Failed to connect to Edera: {}", .{err});
```

4. **Use `zig build --summary all` to see what's being compiled**

5. **Profile with `zig build -Doptimize=ReleaseFast` and compare performance**

---

## Learning Milestones & Blog Posts

Consider writing blog posts at these milestones:

### Post 1: "Building a JSON Parser in Zig" (After Phase 1)
- Design decisions (representation, parsing strategy)
- Allocator choices
- Error handling
- Performance characteristics
- Code samples

### Post 2: "TCP Server from Scratch in Zig" (After Phase 2)
- Socket programming basics
- Buffering strategies
- Connection handling
- Error cases (connection reset, timeout)
- Comparison with Go's `net` package

### Post 3: "Implementing HTTP/1.1 in Zig" (After Phase 4)
- Protocol parsing
- Request/response lifecycle
- Keep-Alive connections
- Performance vs existing servers
- Wire format examples

### Post 4: "Memory Management Patterns in Zig" (After Phase 5)
- Allocator strategies used
- Ownership patterns
- Common pitfalls and solutions
- Comparison with Rust's ownership

### Post 5: "Building a Minimal Orchestrator" (After Phase 6)
- Architecture overview
- End-to-end flow
- Edera integration
- Lessons learned

---

## Research Questions to Explore

As you build, document your answers to these questions:

### JSON Parser
- How does Zig's comptime compare to Rust's macros for JSON parsing?
- What's the performance difference between arena and GPA for parsed data?
- How do you handle streaming JSON (very large documents)?

### TCP/HTTP
- How does Zig's `std.net` compare to Go's `net` package?
- What's the overhead of Zig's error handling vs Go's?
- How would you implement HTTP/2? What changes?

### Memory Management
- When should you use arena allocators vs GPA?
- How do you track down memory leaks?
- What patterns prevent use-after-free bugs?

### Async (Future)
- How does Zig's async model differ from Go's goroutines?
- What's the runtime overhead?
- Can you mix blocking and async code?

### Comptime
- What problems are best solved with comptime?
- How do you debug comptime code?
- What are the limitations?

---

## Success Criteria

You'll know you've succeeded when:

1. **Phase 1:** You can parse and serialize your project's JSON without `std.json`
2. **Phase 2:** Agent accepts TCP connections and handles requests
3. **Phase 3:** Agent maintains state across multiple requests
4. **Phase 4:** Control plane serves HTTP requests and forwards to agent
5. **Phase 5:** End-to-end flow works: curl → CP → agent → response
6. **Phase 6:** Real workload runs in Edera zone via your orchestrator

**Final Test:**
```bash
# Submit a real workload
curl -X POST http://localhost:8080/workloads \
  -d '{"id":"test-1","image":"nginx:latest","runtime_class":"edera-zone","memory_mb":512,"cpu_millicores":500}'

# Wait a moment, then check status
curl http://localhost:8080/workloads/test-1
# Returns: {"id":"test-1","state":"running"}

# Verify in Edera
edera zones list
# Shows: test-1 zone running
```

---

## Your First Task: JSON Parser Design

Before writing code, answer these design questions:

1. **Representation:** How will you represent parsed JSON?
   - Tagged union of all JSON types?
   - Direct to target structs only?
   - Hybrid approach?

2. **Parsing Strategy:**
   - Tokenize first, then parse?
   - Recursive descent directly?
   - State machine?

3. **Memory Allocation:**
   - One arena for all parsed data?
   - Caller-provided allocator?
   - Who owns string memory?
   - When is memory freed?

4. **Error Handling:**
   - What errors can occur?
   - How to report position in JSON for errors?
   - Fail fast or collect errors?

5. **API Design:**
   - Generic parse function: `parse(comptime T: type, json: []const u8)`?
   - Or specific to your types: `parseWorkload(json: []const u8)`?
   - How to handle optional fields?

**Exercise:** Write pseudocode for your parser design before implementing.

**Next Steps:** 
1. Design your JSON parser on paper
2. Implement tokenizer (if using two-phase approach)
3. Implement parser for simple flat objects
4. Test with your Workload type
5. Expand to handle nested structures

Once you have JSON working, everything else follows naturally.

Ready to start? Let me know which phase you'd like to dive into first, and I can provide more detailed guidance!

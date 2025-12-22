# JSON Parser Design References

This document provides curated references to help answer the key design questions in Phase 1 of the Learning Roadmap.

**Note**: As of 2024, Zig's official repository has moved from GitHub to Codeberg. The official repository is now at <https://codeberg.org/ziglang/zig>

## 1. Understanding Zig's std.json (Learn from the Source)

Before building your own, study how Zig's standard library does it:

### Official Zig Source Code

**Note**: Zig has moved from GitHub to Codeberg. The official repository is now at <https://codeberg.org/ziglang/zig>

- **Main JSON module**: <https://codeberg.org/ziglang/zig/src/branch/master/lib/std/json.zig>
  - Shows the overall architecture: Scanner → Parser → Types
  - Uses a tokenization approach (Scanner produces tokens)
  - Has both static parsing (to known types) and dynamic parsing (to Value)

- **Static parsing implementation**: <https://codeberg.org/ziglang/zig/src/branch/master/lib/std/json/static.zig>
  - How to parse JSON directly to Zig structs
  - Comptime magic for automatic struct mapping
  - Error handling patterns

- **Scanner/Tokenizer**: <https://codeberg.org/ziglang/zig/src/branch/master/lib/std/json/scanner.zig>
  - Two-phase approach: tokenize first, then parse
  - How to handle streaming/buffered input

**Key Takeaway**: Zig's std.json uses a Scanner (tokenizer) that produces tokens, then parsers consume those tokens. This is the "two-phase" approach mentioned in the roadmap.

### Tutorials and Guides

- **Zig.guide JSON tutorial**: <https://zig.guide/standard-library/json/>
  - Simple examples of using std.json
  - Shows parseFromSlice and stringify APIs

- **Zig Cookbook - JSON**: <https://cookbook.ziglang.cc/10-01-json/>
  - Practical examples with allocators
  - Demonstrates the allocator requirements

- **Huy's Blog - Zig JSON in 5 minutes**: <https://www.huy.rocks/everyday/01-09-2022-zig-json-in-5-minutes>
  - Quick overview of the API
  - Shows memory management with parseFree

## 2. Allocator Deep Dive (Critical for Understanding)

Memory allocation is central to JSON parsing. You need to decide where parsed data lives and who owns it.

### Official Documentation

- **Zig.guide Allocators**: <https://zig.guide/standard-library/allocators/>
  - Best starting point for understanding allocators
  - Examples of page_allocator, ArenaAllocator, GPA, FixedBufferAllocator

- **Arena Allocator Source**: <https://codeberg.org/ziglang/zig/src/branch/master/lib/std/heap/arena_allocator.zig>
  - How ArenaAllocator works internally
  - Perfect for "allocate many, free once" patterns

### Tutorials

- **Introduction to Zig - Memory and Allocators**: <https://pedropark99.github.io/zig-book/Chapters/01-memory.html>
  - Comprehensive guide to memory management in Zig
  - Explains heap vs stack, ownership, and allocator patterns

- **Learning Zig - Heap Memory & Allocators**: <https://www.openmymind.net/learning_zig/heap_memory/>
  - Practical examples with real code
  - Common pitfalls like double-free and memory leaks
  - When to use defer for cleanup

- **Zig Allocators Explained**: <https://dayvster.com/blog/zig-allocators-explained/>
  - Clear comparison of different allocator types
  - When to use each one

- **How ArenaAllocator Works**: <https://www.huy.rocks/everyday/01-12-2022-zig-how-arenaallocator-works>
  - Deep dive into arena internals
  - How it manages the buffer list

- **Brief Guide to Zig Allocators**: <https://abbychau.github.io/article/a-brief-and-complete-guide-of-zig-allocators>
  - Quick reference for all allocator types
  - Memory pool patterns

### Key Decisions for Your Parser

1. **Should parsed JSON use an ArenaAllocator?**
   - Pro: Free everything at once when done parsing
   - Pro: Fast allocation, no individual frees needed
   - Con: All memory lives until arena.deinit()
   - **Best for**: Request handlers, one-off parsing

2. **Should you use GeneralPurposeAllocator?**
   - Pro: Memory leak detection
   - Pro: Use-after-free detection
   - Pro: Fine-grained control
   - Con: Must free each allocation individually
   - **Best for**: Long-lived registries, development/debugging

3. **Who owns string memory?**
   - Option A: Parser copies all strings (safe, uses more memory)
   - Option B: Parser keeps references to input (fast, but input must stay alive)

## 3. Parsing Theory and Techniques

### Recursive Descent Parsing

- **Building Recursive Descent Parsers - Definitive Guide**: <https://www.booleanworld.com/building-recursive-descent-parsers-definitive-guide/>
  - Excellent theory and practice
  - Builds both a calculator and JSON parser
  - Python examples (easy to translate to Zig)

- **Wikipedia - Recursive Descent Parser**: <https://en.wikipedia.org/wiki/Recursive_descent_parser>
  - Formal definition
  - LL(k) grammars
  - Predictive parsing vs backtracking

- **Building a Recursive Descent Parser in Rust (Part 1)**: <https://home-xero.vercel.app/blog/building-a-recursive-descent-parser-in-rust-01>
  - Very similar to what you'll build in Zig
  - Shows tokenization phase
  - Context-free grammar explanation

- **Recreating JSON.parse (JavaScript)**: <https://dev.to/wpreble1/a-recursive-descent-recreating-json-parse-1icb>
  - Mutual recursion explained well
  - JSON grammar visualization

### Key Concepts

**Tokenization vs Direct Parsing:**

- **Tokenization (Two-phase)**: Text → Tokens → AST
  - Clearer separation of concerns
  - Easier error messages (can point to exact token)
  - What Zig's std.json does

- **Direct Parsing (Recursive Descent)**: Text → AST
  - Fewer passes over the data
  - Can be simpler for simple grammars
  - Still uses recursion

**Recursive Descent Pattern:**

```
For each grammar rule, write a function:
- parseObject() for { ... }
- parseArray() for [ ... ]
- parseValue() for any value
- parseString() for "..."
- parseNumber() for numbers

Each function:
1. Checks what comes next
2. Calls appropriate sub-parsers
3. Builds up the result
4. Returns or errors
```

## 4. The Official JSON Specification

Understanding exactly what you need to parse:

### RFC 8259 - The JSON Specification

- **Full RFC**: <https://datatracker.ietf.org/doc/html/rfc8259>
  - Section 2: JSON Grammar (critical!)
  - Section 7: Strings and escape sequences
  - Section 6: Numbers (int vs float, scientific notation)

- **RFC Info Page**: <https://www.rfc-editor.org/info/rfc8259>

- **Medium Article - RFC 8259 Explained**: <https://medium.com/@linz07m/rfc-8259-the-json-data-interchange-format-5e8fe8c01dd2>
  - More accessible explanation
  - Examples

### JSON Grammar (from RFC 8259)

```
JSON-text = ws value ws

value = object / array / string / number / "true" / "false" / "null"

object = begin-object [ member *( value-separator member ) ] end-object

member = string name-separator value

array = begin-array [ value *( value-separator value ) ] end-array

string = quotation-mark *char quotation-mark

number = [ minus ] int [ frac ] [ exp ]
```

**Key Edge Cases to Handle:**

1. **Strings**: Escape sequences (`\"`, `\\`, `\n`, `\t`, `\uXXXX`)
2. **Numbers**: `-0`, scientific notation (`1e10`, `1E-5`), no leading zeros
3. **Whitespace**: Can appear before/after any token
4. **Unicode**: UTF-8 encoding, surrogate pairs for characters outside BMP

## 5. Example Implementations to Study

### Simple JSON Parsers in Various Languages

- **json-zig (Zig)**: <https://github.com/joechung2008/json-zig>
  - Complete Zig implementation you can study
  - Shows both parsing and serialization

- **Myna Parser (JavaScript)**: <https://cdiggins.github.io/myna-parser/>
  - Recursive descent library with JSON example
  - Shows grammar-driven approach

- **rd-parse (JavaScript)**: <https://github.com/dmaevsky/rd-parse>
  - Generic recursive descent parser
  - Shows combinator approach

## 6. Answering Your Phase 1 Design Questions

Now you have the resources to answer these questions from the roadmap:

### Question 1: JSON Representation

**"How will you represent parsed JSON before mapping to structs?"**

Study these files to decide:

- Zig's `Value` type: <https://codeberg.org/ziglang/zig/src/branch/master/lib/std/json/dynamic.zig>
- Shows tagged union approach

**Your options:**

```zig
// Option A: Tagged union (flexible like std.json)
const Value = union(enum) {
    null,
    bool: bool,
    number: f64,
    string: []const u8,
    array: []Value,
    object: std.StringHashMap(Value),
};

// Option B: Direct to Workload (simpler for your specific needs)
// Just parse JSON directly to your types
// No intermediate representation
```

**Research question**: Do you need to parse arbitrary JSON, or just your known types (Workload, RPC messages)?

### Question 2: Parsing Strategy

**"Tokenize first or parse directly?"**

Read these to decide:

- How std.json does it: Two-phase with Scanner
- Recursive descent examples: Often skip tokenization

**Your options:**

```zig
// Option A: Two-phase (like std.json)
const tokens = try tokenize(allocator, json_text);
const value = try parse(allocator, tokens);

// Option B: Direct recursive descent
const value = try parseValue(allocator, json_text, &pos);
```

**Tradeoff**: Two-phase is clearer but slower. Direct is faster but mixes concerns.

### Question 3: Memory Allocation Strategy

**"Who owns the memory? When is it freed?"**

Review the allocator guides, then decide:

```zig
// Strategy 1: Arena for entire parse
var arena = std.heap.ArenaAllocator.init(gpa.allocator());
defer arena.deinit();
const parsed = try parseWorkload(arena.allocator(), json);
// Everything freed when arena.deinit() called
// Fast, simple, perfect for request handlers

// Strategy 2: Caller-provided allocator
pub fn parse(allocator: Allocator, json: []const u8) !Workload {
    // Allocate as needed
    // Caller must free later
}
// More flexible but caller has more responsibility

// Strategy 3: Mixed - Arena internally, return owned result
pub fn parse(result_allocator: Allocator, json: []const u8) !Workload {
    var arena = std.heap.ArenaAllocator.init(result_allocator);
    defer arena.deinit();
    // Use arena for temporary parsing structures
    // But copy final result to result_allocator
    const workload = try allocateAndCopyResult(result_allocator, temp_workload);
    return workload;
}
```

### Question 4: Error Handling

**"What errors can occur? How to report position?"**

Study `std.json` error types:

```zig
pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEndOfInput,
    InvalidNumber,
    InvalidEscapeSequence,
    // ... etc
};
```

Consider adding position info:

```zig
pub const ParseError = struct {
    err: Error,
    position: usize,  // Character position in input
    line: usize,      // Line number
    column: usize,    // Column number
};
```

### Question 5: API Design

**"Generic or specific?"**

```zig
// Option A: Generic (like std.json)
pub fn parse(comptime T: type, allocator: Allocator, json: []const u8) !T

// Option B: Specific to your types
pub fn parseWorkload(allocator: Allocator, json: []const u8) !Workload
pub fn parseRpcMessage(allocator: Allocator, json: []const u8) !RpcMessage

// Option C: Hybrid
pub fn parse(comptime T: type, allocator: Allocator, json: []const u8) !T
// But only implement for your specific types
```

## 7. Recommended Study Order

1. **Start here**: Read the Zig.guide allocators page thoroughly
2. **Then**: Skim the std.json source code (don't try to understand everything)
3. **Next**: Read one of the recursive descent parser tutorials
4. **Then**: Read RFC 8259 Section 2 (JSON Grammar)
5. **Finally**: Study the "Learning Zig - Heap Memory" article

After this, you'll be ready to make your design decisions!

## 8. Practical Exercises Before Implementation

### Exercise 1: Allocator Playground

```zig
// Experiment with different allocators
const std = @import("std");

pub fn main() !void {
    // Try ArenaAllocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    
    const allocator = arena.allocator();
    
    // Allocate some strings
    const s1 = try allocator.dupe(u8, "hello");
    const s2 = try allocator.dupe(u8, "world");
    
    // No need to free individually!
    // arena.deinit() frees everything
    
    std.debug.print("{s} {s}\n", .{s1, s2});
}
```

### Exercise 2: Simple Tokenizer

```zig
// Write a tokenizer for a tiny subset: just numbers and braces
const Token = union(enum) {
    number: f64,
    brace_open,
    brace_close,
};

pub fn tokenize(input: []const u8) ![]Token {
    // Your implementation here
    // Learn about: iterating characters, parsing numbers, ArrayList
}
```

### Exercise 3: Parse Simple JSON

```zig
// Parse just: {"key": "value"}
// No nested objects, no arrays, just one string key-value pair
pub fn parseSimpleObject(json: []const u8) !std.StringHashMap([]const u8) {
    // Your implementation here
    // Learn about: state machines, string matching
}
```

## 9. Questions to Answer Before Writing Code

Write down your answers to these:

1. **Will you need to parse arbitrary JSON, or just your known types?**
   - Answer determines if you need Value union or can go directly to structs

2. **How long does parsed data need to live?**
   - Answer determines if ArenaAllocator is appropriate

3. **Do you want the best error messages possible?**
   - Answer determines if you should tokenize first (better errors) or parse directly (simpler)

4. **What's your priority: learning depth or getting it working?**
   - Learning depth → implement both approaches, compare them
   - Getting it working → start with recursive descent, no tokenization

## Next Steps

Once you've reviewed these resources and answered the design questions:

1. Create a new file `docs/json-design-decisions.md` documenting your choices
2. Write pseudocode for your parser
3. Implement the simplest possible JSON parser (just numbers and strings)
4. Expand incrementally (add objects, arrays, booleans, null)
5. Add your Workload type parsing
6. Add error handling and edge cases

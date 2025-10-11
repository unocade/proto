# 🧩 Unocade Proto Repository

> Centralized gRPC/protobuf definitions for all Unocade microservices.

---

## 📚 Overview

The `proto` repository contains **all shared `.proto` files** that define the **gRPC services, messages, and contracts** used across Unocade microservices.

- Ensures **type-safe communication** between services.
- Prevents duplicate or inconsistent message definitions.
- Supports **code generation** for Go and other languages (future frontend use).

---

## 📁 Repository Structure

```
proto/
├── user.proto           # User Management Service definitions
├── match.proto          # Matchmaking / Lobby definitions
├── common.proto         # Shared types (e.g., timestamps, IDs)
├── Makefile             # Code generation helper
└── README.md
```

---

## ⚙️ Setup & Code Generation

### 1. Install Protobuf Compiler

```bash
# MacOS
brew install protobuf

# Ubuntu
sudo apt install -y protobuf-compiler
```

### 2. Install Go gRPC Plugin

```bash
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
export PATH="$PATH:$(go env GOPATH)/bin"
```

### 3. Generate Go Code

Use the included Makefile:

```makefile
PROTOC_GEN_GO=$(shell which protoc-gen-go)
PROTOC_GEN_GO_GRPC=$(shell which protoc-gen-go-grpc)

generate:
	protoc --go_out=../ --go-grpc_out=../ *.proto
```

Run:

```bash
make generate
```

This will generate **Go code** in each service repo's `pb/` directory.

---

## ⚙️ Adding a New Service

1. Create a new `.proto` file (e.g., `game.proto`)
2. Define **service**, **messages**, and **enums**
3. Add generation rule to Makefile if needed
4. Commit and push → all services can now import the generated Go package

---

## ⚙️ Usage in Go Services

Example usage in **UMS**:

```go
import (
	userpb "github.com/unocode/proto/pb/user"
)

func main() {
	// Implement gRPC server using generated code
}
```

All services will import from `github.com/unocode/proto/pb/<service>`.

---

## 🚀 Best Practices

- Keep messages **small and focused**.
- Avoid service-specific business logic inside proto files.
- Use `common.proto` for shared types like `ID`, `Timestamp`, `Error`.
- Increment **proto file versions** if breaking changes are introduced.

---

## 🧠 Future Plans

- Add **game.proto** → for Game Management Service
- Add **analytics.proto** → for leaderboard & stats
- Add **notification.proto** → for Event/Notification Service

---

This README serves as the **single source of truth** for all gRPC contracts in Unocade.

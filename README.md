# 🧩 Unocade Proto Repository

> Centralized gRPC/protobuf definitions for all Unocade microservices.

---

## 📚 Overview

This repository holds every shared `.proto` file and the **committed** generated Go code for them.

- `.proto` files in `proto/` are the source of truth for every gRPC contract in Unocade.
- Generated Go lives in `pb/` as **one flat package** (`pb`) — there are no per-service subpackages.
- Services import it as `github.com/unocade/proto/pb`.

```go
import pb "github.com/unocade/proto/pb"
```

---

## 📁 Repository Structure

```
proto/
├── proto/                     # .proto sources
│   ├── cache.proto            # CacheService        (CMS) — KV, hashes, counters, pub/sub, queue
│   ├── common.proto           # shared messages (no service)
│   ├── engine.proto           # EngineService       — the pluggable game-engine contract
│   ├── game.proto             # GameService         (GMS) — lobby/match lifecycle
│   ├── token.proto            # TokenService        (TMS)
│   └── user.proto             # UserService         (UMS)
├── templates/                 # untracked scaffold for a new engine's proto
├── pb/                        # GENERATED, gitignored — produced by `make generate`
├── .gitignore
├── .protolint.yaml            # proto lint config
├── makefile                   # the only codegen path
├── .github/workflows/         # ci.yaml — lint, build, and the release pipeline
└── go.mod                     # module github.com/unocade/proto
```

`common.proto` holds only shared *messages* — `RegisterServiceRequest`, `RegisterServiceResponse`, `HealthCheckRequest`, `HealthCheckResponse`, `Empty`, `Player`.

---

## ⚙️ Setup & Code Generation

### 1. Install the pinned toolchain

Versions are pinned because the generated files embed them in their headers — a different plugin version produces a diff in every generated file.

| Tool                | Version   |
| ------------------- | --------- |
| `protoc`            | `3.21.12` |
| `protoc-gen-go`     | `1.36.11` |
| `protoc-gen-go-grpc`| `1.6.1`   |

```bash
# protoc v3.21.12 — download from protocolbuffers/protobuf releases v21.12
# Linux: unzip protoc-21.12-linux-x86_64.zip -d protoc && export PATH="$PATH:$PWD/protoc/bin"

go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.36.11
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.6.1
export PATH="$PATH:$(go env GOPATH)/bin"
```

### 2. Generate

Run from the repository root (the makefile's paths are relative to the CWD):

```bash
make generate
```

which is:

```bash
mkdir -p pb && protoc --proto_path=proto --go_out=pb --go_opt=paths=source_relative \
       --go-grpc_out=pb --go-grpc_opt=paths=source_relative proto/*.proto
```

`--proto_path=proto` is what lets protos import each other by bare filename (`import "common.proto";`). `paths=source_relative` makes `pb/` mirror the proto filenames 1:1. The `mkdir -p pb` is needed because protoc does not create the output directory and `pb/` is gitignored.

**Do not install the plugins with `@latest`** — a newer plugin rewrites the version comment in every `*_grpc.pb.go`, and CI will then commit that cosmetic churn back to `dev` on the next proto change.

---

## ➕ Adding a New Service

1. Create `proto/<name>.proto` with `package <name>;` and `option go_package = "./;pb";`.
2. Define the service, messages, and enums. Import shared types with `import "common.proto";`.
3. Run `make generate` locally so you can build — **CI publishes the generated `pb/` to `master`** (see below).
4. Commit the `.proto` and push to `dev`. CI lints it, regenerates `pb/`, publishes it to `master`, then tags and releases.

The makefile globs `proto/*.proto`, so **no makefile edit is needed** (but a proto in a subdirectory would be silently skipped).

Because everything flattens into a single Go package, **message names must be unique across all proto packages** — `common.Player` becomes `pb.Player`. A duplicate name in another package is a Go compile error, not a proto error.

---

## 🔌 Using It From a Service

```go
import pb "github.com/unocade/proto/pb"
```

Services pin a released version, e.g. `github.com/unocade/proto v0.1.5-dev`. Each release published by CI is a `vX.Y.Z-dev` prerelease tag on a `master` commit, so bump your pin to the newest one.

For local development add a `replace` directive:

```
replace github.com/unocade/proto => ../proto
```

`replace` is not transitive — only the **main** module's replaces apply, so a service that replaces `service-utils` but not `proto` still resolves `proto` from the network.

> A `replace` to a local checkout now needs `make generate` to have been run in that checkout, because `pb/` is gitignored and no longer committed to `dev`.

---

## 🌿 Branches

| Branch | Contents | Updated by |
| --- | --- | --- |
| `dev` | the `.proto` sources — the source of truth. No `pb/`: it is gitignored. | humans, via pull requests |
| `master` | the sources **plus** the generated `pb/` — the published branch | CI only |

`pb/` is generated on every push to `dev` and published to `master` by CI, which then cuts the version tag and the release. **Do not commit `pb/` changes** — `master` owns the generated code, and a hand-committed `pb/` makes the `dev` → `master` merge conflict on generated files.

Because `pb/` is gitignored, a fresh checkout has no Go package at all. **Run `make generate` before building** — `go build ./...` on a checkout without `pb/` matches no packages and exits 0, which is a vacuous pass, not a real build.

---

## 🧪 CI

One workflow: `.github/workflows/ci.yaml` (`proto-ci`), on GitHub-hosted `ubuntu-latest`. It runs on every push (any branch) and on manual dispatch — there is no `pull_request` trigger. Two jobs:

| Job | What it does | Runs on |
| --- | --- | --- |
| `lint` | `protolint lint .protolint.yaml proto/` | every push, no branch restriction |
| `proto` | pinned toolchain → `make generate` → publish | push to `dev`, or manual dispatch on `dev`/`master` |

The `proto` job is restricted the same way the publish is — a push to `dev`, or a manual `workflow_dispatch` on `dev` or `master`. A push to `master` — which is what the job itself does — never generates or publishes again.

The publish itself does two things:

1. **publish** — the regenerated `pb/` is committed to `master` as `502BadPing <aditya.sen1hl@gmail.com>`
2. **release** — a `vX.Y.Z-dev` tag is cut on that `master` commit and a prerelease is published

A push to `master` never publishes — the workflow cannot publish on the `master` push it makes itself. Use a manual `workflow_dispatch` on `dev` or `master` to force one.

There is no test suite, build, or formatter gate in this repo. `make generate` is the only validation: protoc fails outright on a broken `.proto`, so it doubles as the compile check.

### The token

The publish uses the workflow's own **`GITHUB_TOKEN`** with `permissions: contents: write` — no PAT is needed. The *commit author* is `502BadPing <aditya.sen1hl@gmail.com>`, set through the job's `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env vars, because the runner image ships no git identity and `git commit-tree` / `git tag -a` fail with "empty ident name ... not allowed" without one.

Two consequences:

- **The push is attributed to `github-actions[bot]`,** while the commit itself is authored by `502BadPing`. On the commit page you get "authored by 502BadPing" and "pushed by github-actions[bot]".
- **The auto-commit does not re-trigger the workflow.** GitHub ignores workflow runs caused by pushes made with `GITHUB_TOKEN`, so the generated commit does not start another run. That is what keeps the pipeline from looping.

### Things worth knowing

- **`master` must allow the workflow token to push.** If the branch is protected against it, the publish step fails.
- **A release only happens when the generated output actually changed.** `pb/` is regenerated on every `dev` push, but it only commits and tags if the result differs. A comment-only proto change does not alter the descriptor, so there is no commit and no release.
- **The publish is a fast-forward.** The new `master` commit is built with its parent set to `master`'s tip, so no force push and no history rewrite.

### Proto lint rules

`.protolint.yaml` keeps protolint's default rule set minus two:

- `FIELD_NAMES_LOWER_SNAKE_CASE` — renaming `ID` → `id` or `avatarURL` → `avatar_url` changes the generated Go identifiers (`pb.Player.ID` → `.Id`) *and* the proto3 JSON names, which breaks `user-management-service` and the frontend.
- `REPEATED_FIELD_NAMES_PLURALIZED` — `value` → `values` changes `pb.GetAllResponse.Value` to `.Values`, breaking `cache-management-service`.

Re-enabling either is an org-wide breaking change that needs a rename pass across every consuming service.

---

## 📝 Notes

- `HealthCheck` and `RegisterService` are declared on every service, but **no engine implements them** — they fall through to `codes.Unimplemented`. Engines register the stdlib `grpc_health_v1` server instead; point probes there.
- `MakeMoveRequest.movePayload` and `GetStateResponse.statePayload` are `bytes` and deliberately game-specific. Each engine defines its own JSON wire format; there is no shared schema.
- `engine.proto` is the contract every game engine implements (`InitGame`, `MakeMove`, `GetState`).

---

The `.proto` files in `proto/` are the single source of truth for all gRPC contracts in Unocade.

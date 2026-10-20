# AGENTS.md — `unocade/proto`

Shared gRPC/protobuf contracts for all Unocade services. Cross-repo facts live in `../AGENTS.md`; this file covers only this module.

## Layout

- `proto/*.proto` — the source of truth. Tracked files: `cache`, `common`, `engine`, `game`, `token`, `user`.
- `pb/*.pb.go` — **generated and gitignored.** It is *not* on `dev`; CI publishes it to `master`. Run `make generate` to produce it locally. One **flat package `pb`** (`github.com/unocade/proto/pb`); there are no per-service subpackages. Every proto declares `option go_package = "./;pb";`, which is what names that package.
- `templates/engine_service_template.proto` — an untracked copy-paste scaffold for new engines. It is **not** in `proto/`, so it does not break codegen.
- `makefile` — the **only** codegen path. No `buf.yaml`, no `go:generate`, no `scripts/`.
- `.github/workflows/ci.yaml` — the only CI: lint, build, and the release pipeline.
- Default branch is `dev` (not `main`).

## Branches

- **`dev`** — the source of truth for the `.proto` files. It carries **no `pb/`**: the directory is gitignored and regenerated on demand.
- **`master`** — the published branch: the sources plus the generated `pb/`. CI-only; humans do not push to it. All version tags point at `master` commits.
- **Never hand-commit `pb/`.** `master` owns the generated code, and a hand-committed `pb/` makes the `dev` → `master` merge conflict on generated files.

## Codegen

```bash
# from the repo root; paths are CWD-relative
make generate
# = mkdir -p pb && protoc --proto_path=proto --go_out=pb --go_opt=paths=source_relative \
#          --go-grpc_out=pb --go-grpc_opt=paths=source_relative proto/*.proto
```

- **`make generate` is required before building.** `go build ./...` on a fresh clone matches no packages and exits 0 — a vacuous pass, not a real build. Always generate first.
- The makefile creates `pb/` itself: protoc does not create the output directory, and `pb/` is gitignored so a fresh checkout has none.
- The makefile globs `proto/*.proto` (non-recursive). Adding a `.proto` to `proto/` needs no makefile edit; a proto in a subdirectory would be silently skipped.
- `--proto_path=proto` means protos import each other by bare filename (`import "common.proto";`), never by proto package.
- `paths=source_relative` makes `pb/` mirror the proto filenames 1:1.

### Toolchain on this machine (verified)

- **`protoc` is NOT installed.** The two Go plugins are installed in `$(go env GOPATH)/bin`, which is **not on `PATH`**:
  - `protoc-gen-go` **v1.36.11** (matches CI)
  - `protoc-gen-go-grpc` **v1.6.2** — **does not match CI's v1.6.1**
- **Plugin version drift shows up as a one-line diff.** The generated header embeds the plugin version (`// - protoc-gen-go-grpc v1.6.1`). Regenerating with the local v1.6.2 changes *only* that comment line in every `*_grpc.pb.go`. CI used to reject that as drift; now it silently **auto-corrects** it, so you will get a surprise "regenerate protobuf bindings" commit. Install the pinned version:
  ```bash
  GOBIN=$(go env GOPATH)/bin go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.6.1
  # protoc v3.21.12 — download from protocolbuffers/protobuf releases v21.12
  ```
- With pinned `protoc 3.21.12` + `protoc-gen-go v1.36.11` + `protoc-gen-go-grpc v1.6.1`, regeneration is **byte-identical** to the committed `pb/`.

## CI: One Workflow (`.github/workflows/ci.yaml`)

`proto-ci`, on `ubuntu-latest`, triggered on **every push** (any branch) and on manual dispatch. There is **no `pull_request` trigger**. Two jobs:

- **`lint`** — no branch restriction: `protolint lint .protolint.yaml proto/`. This is the only job that runs on every branch.
- **`proto`** (generate and publish) — `needs: lint`, so lint gates the generation and the release. Pinned toolchain → `make generate` → publish.

**No `go vet`, no `gofmt`, no `golangci-lint`, no `go build`, no tests.** There is no `.golangci.yml` in this repo (it is excluded from the org lint path). `make generate` is the only validation: protoc fails outright on a broken `.proto`, so it doubles as the compile check.

The `proto` job is **restricted the same way the publish is**: it runs only on a **push to `dev`**, or a manual `workflow_dispatch` on `dev` or `master`. A push to `master` — which is what the job itself does — never generates or publishes again.

The `proto` job then publishes, but only on a **push to `dev`**, or a manual `workflow_dispatch` on `dev` or `master`:

1. commit the regenerated `pb/` to **`master`** as `502BadPing <aditya.sen1hl@gmail.com>`
2. tag `vX.Y.Z-dev` (patch bump over the newest tag) on that `master` commit and publish a prerelease

Gotchas that are not obvious from the YAML:

- **A push to `master` never publishes.** Only a push to `dev` drives the publish, so the workflow cannot publish on the `master` push it makes itself. A manual `workflow_dispatch` on `dev` or `master` can force one.
- **The publish builds the commit with plumbing, not a checkout.** `git write-tree` captures the tree (checkout tree + regenerated `pb/`), and `git commit-tree` creates the commit with `master`'s tip as its parent — so the push is always a **fast-forward**: no force push, no history rewrite. The first publish uses the pushed branch's HEAD as the parent, so `master` is created on the fly.
- **`pb/` is gitignored, so the publish step force-adds it** (`git add -A -f pb/`). Without `-f` the generated files would be silently skipped and `master` would get an empty `pb/`.
- **`master` is never committed to directly.** The publish step compares the new tree against `master`'s current tree; if they match it exits without committing, so repeated runs are no-ops.
- **The push and the release use a PAT, not `GITHUB_TOKEN`.** `secrets.ACCESS_TOKEN` must be a personal access token with write access to this repo. The workflow token itself stays read-only (`permissions: contents: read`) — the PAT is passed as an `http.https://github.com/.extraheader` on the push, exactly like `actions/checkout` does it.
- **A PAT push *does* re-trigger CI** (a `GITHUB_TOKEN` push would not). The re-run finds `master` already up to date, so it publishes nothing — no loop, but it does cost a second run.
- **`cancel-in-progress: false`** — the workflow mutates the repo, so a half-finished publish run must not be cancelled.
- A proto **comment-only** change does not alter the descriptor, so `pb/` is unchanged → no commit, no tag, no release. That is intentional.
- The job regenerates on **every** push to `dev` or `master`, not just proto changes — that is what makes drift self-healing. It only commits and tags when `pb/` actually differs.

## Proto Lint (`.protolint.yaml`)

`protolint lint .protolint.yaml proto/` must be clean. The config keeps protolint's default rule set **minus** `FIELD_NAMES_LOWER_SNAKE_CASE` and `REPEATED_FIELD_NAMES_PLURALIZED` — both are excluded because enforcing them is a **cross-repo breaking change**, not a lint preference:

- `ID` → `id` / `avatarURL` → `avatar_url` changes the generated Go identifiers (`pb.Player.ID` → `.Id`, `pb.UserResponse.AvatarURL` → `.AvatarUrl`) **and** the proto3 JSON names. Breaks `user-management-service` (`domain/user.go`, `grpcserver/grpchandler.go`) and the frontend's JSON payloads.
- `value` → `values` changes `pb.GetAllResponse.Value` → `.Values`. Breaks `cache-management-service/grpcserver/redis.go`.

**Do not re-enable either rule** without a rename pass across every consuming service. Also note `all_default: true` in a protolint config means *every* rule including the optional comment rules — it does **not** mean "the default set". The config deliberately leaves it unset.

## Landmine: `templates/engine_service_template.proto`

It used to live at `proto/engine_service_template.proto`, where it declared the **same proto package `engine` and the same `service EngineService`** as `engine.proto`. Because the makefile globs `proto/*.proto`:

- `make generate` **fails outright** with ~30 protoc "already defined in file engine.proto" errors and exit code 2. Nothing is written — `pb/` is left untouched (verified).
- It now lives in `templates/` (still untracked) so it cannot break codegen. **Do not move it back into `proto/`** and do not add it to git.

## Working Tree

`git status` shows `?? AGENTS.md`, `?? .gitignore`, `?? .protolint.yaml`, `?? templates/`, `?? tempci.yml` (the reference workflow you dropped in — **delete it, it is not part of the repo**), `M README.md`, `M .github/workflows/ci.yaml` (runner switched `self-hosted` → `ubuntu-latest`, uncommitted, pre-existing — do not revert it) and the six cleaned `proto/*.proto` files.

There is no `M go.sum` (older notes claiming that are stale).

## Verifying a change

```bash
make generate                                       # pb/ is gitignored; generate it first
go build ./... && go vet ./... && gofmt -l pb       # all currently clean
go test ./...                                       # no test files; compile check only
protolint lint .protolint.yaml proto/               # must be clean; protolint is NOT installed locally
```

There are no checked-in Go tests in this repo.

## Proto Authoring Conventions

- **Never hand-roll request/response structs** in a service. Add the message here and regenerate.
- Because everything flattens into one Go package, **message names must be unique across all proto packages** (`common.Player` → `pb.Player`). A duplicate name in another package is a Go compile error, not a proto error.
- Every service declares `HealthCheck` / `RegisterService` with the shared `common.HealthCheckRequest` / `common.RegisterServiceResponse` from `common.proto`. **`HealthCheck` and `RegisterService` are implemented by no engine** — they fall through to `codes.Unimplemented`. Don't point probes at them; engines register the stdlib `grpc_health_v1` server instead.
- `MakeMoveRequest.movePayload` and `GetStateResponse.statePayload` are `bytes` and explicitly game-specific. Each engine defines its own JSON wire format; there is no shared schema.
- Header order is `syntax` → `package` → `import` → `option` → body, one blank line between blocks. That is what the protolint `IMPORTS_SORTED` / `INDENT` / `MAX_LINE_LENGTH` rules expect, and it is byte-identical in the generated output.

## `README.md` Was Rewritten (2026-10-20)

It used to be wrong — it claimed a per-service import path (`github.com/unocode/proto/pb/<service>`, wrong org *and* a subpackage that never existed), listed a nonexistent `match.proto`, showed a protoc invocation that fails outright (no `--proto_path`, output to `../`), told you to install plugins with `@latest`, and said `game.proto` was still to be added.

It now matches the repo: pinned toolchain table, the real `make` invocation, the flat `pb` import path, the actual file list, and the CI pipeline. **If you change codegen, the `makefile`, the pinned versions, or the CI pipeline, update `README.md` in the same commit** — it is the only human-facing description of the codegen contract.

Still trust `makefile` and the `.proto` files over any prose.

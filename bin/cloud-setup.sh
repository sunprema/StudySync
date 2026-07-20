#!/usr/bin/env bash
#
# cloud-setup.sh — provision a fresh Linux container to build & test StudySync.
#
# StudySync is an Elixir/Phoenix/Ash app. A blank cloud container (e.g. Claude
# Code on the web) ships with none of what it needs: Erlang/OTP, Elixir, or a
# running PostgreSQL. Run this ONCE as the environment's setup/bootstrap step —
# not inside the coding agent's own session — so the toolchain is ready before
# any feature work starts.
#
# It is idempotent: safe to re-run. It installs Erlang/Elixir via mise (pinned
# by .tool-versions), starts PostgreSQL, provisions the dev (:5433) and test
# (:5432) databases with role postgres/password postgres to match
# config/dev.exs and config/test.exs, and fetches deps.
#
# Assumes a Debian/Ubuntu base with apt and sudo. Verify success at the end with:
#   mix test        # runs `ash.setup` automatically against the :5432 test DB
#
set -euo pipefail

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m[warn] %s\033[0m\n' "$*"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

# ---------------------------------------------------------------------------
# 1. System packages: build toolchain (for compiling Erlang), Postgres, Node.
# ---------------------------------------------------------------------------
log "Installing system packages (build deps, PostgreSQL, Node)"
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -y
$SUDO apt-get install -y --no-install-recommends \
  build-essential automake autoconf libncurses-dev libssl-dev \
  m4 libwxgtk3.2-dev libgl1-mesa-dev libglu1-mesa-dev libpng-dev \
  unixodbc-dev xsltproc fop libxml2-utils \
  curl git unzip ca-certificates \
  postgresql postgresql-contrib \
  nodejs npm \
  || warn "Some apt packages failed to install; continuing (wxWidgets/docs deps are optional for headless builds)."

# ---------------------------------------------------------------------------
# 2. Erlang + Elixir via mise, pinned by .tool-versions.
#    (apt's Elixir on Ubuntu is often < 1.15, which mix.exs rejects.)
# ---------------------------------------------------------------------------
if ! command -v elixir >/dev/null 2>&1 || ! elixir -e 'System.version() |> Version.match?("~> 1.15") || System.halt(1)' 2>/dev/null; then
  log "Installing Erlang/Elixir via mise (per .tool-versions)"
  if ! command -v mise >/dev/null 2>&1; then
    curl -fsSL https://mise.run | sh
  fi
  export PATH="$HOME/.local/bin:$PATH"
  eval "$(mise activate bash)" || true
  mise trust "$REPO_ROOT/.tool-versions" || true
  # Erlang compiles from source here — this is the slow step (several minutes).
  KERL_CONFIGURE_OPTIONS="--without-javac --without-wx --without-odbc" \
    mise install
  eval "$(mise env -s bash)" || true
  # Make the shims available to the rest of this script.
  export PATH="$HOME/.local/share/mise/shims:$PATH"
else
  log "Elixir $(elixir --version | tail -1) already present — skipping BEAM install"
fi

log "Elixir/Erlang versions"
elixir --version || { warn "elixir not on PATH; open a new shell or run: eval \"\$(mise activate bash)\""; }

# ---------------------------------------------------------------------------
# 3. Hex + Rebar.
# ---------------------------------------------------------------------------
log "Installing Hex and Rebar"
mix local.hex --force
mix local.rebar --force

# ---------------------------------------------------------------------------
# 4. PostgreSQL: start the default cluster on :5432 (test DB), add a second
#    cluster on :5433 (dev DB). Role postgres / password postgres for both.
# ---------------------------------------------------------------------------
log "Starting PostgreSQL"
$SUDO service postgresql start || warn "service postgresql start failed; will still try pg_ctlcluster"

PGVER="$(ls /usr/lib/postgresql/ 2>/dev/null | sort -V | tail -1 || true)"

start_cluster_on_port() {
  local name="$1" port="$2"
  if [ -z "${PGVER:-}" ]; then warn "No PostgreSQL install found; cannot create '$name' cluster."; return 0; fi
  if ! $SUDO pg_lsclusters -h 2>/dev/null | awk '{print $2}' | grep -qx "$name"; then
    log "Creating PostgreSQL cluster '$name' on port $port"
    $SUDO pg_createcluster "$PGVER" "$name" --port "$port" -- --auth-local=trust || warn "pg_createcluster $name failed"
  fi
  $SUDO pg_ctlcluster "$PGVER" "$name" start || warn "starting cluster '$name' failed (may already be running)"
}

set_password_and_dev_db() {
  local port="$1" make_db="$2"
  # ALTER the postgres role's password on the cluster reachable at $port.
  $SUDO -u postgres psql -p "$port" -c "ALTER USER postgres PASSWORD 'postgres';" \
    || warn "could not set postgres password on :$port"
  if [ -n "$make_db" ]; then
    $SUDO -u postgres psql -p "$port" -tc "SELECT 1 FROM pg_database WHERE datname='$make_db'" \
      | grep -q 1 || $SUDO -u postgres psql -p "$port" -c "CREATE DATABASE $make_db;" \
      || warn "could not create database $make_db on :$port"
  fi
}

# Default cluster ("main") normally comes up on :5432 — that's the TEST DB.
# mix test creates/migrates studysync_test itself via `ash.setup`, so we only
# need the role/password here.
set_password_and_dev_db 5432 ""

# Second cluster for the DEV DB on :5433 (config/dev.exs). Best-effort:
# mix ash.codegen (used to generate Slice 23's migration) does NOT need a DB,
# so tests on :5432 are the critical path; :5433 is for running the app/migrations.
start_cluster_on_port dev 5433
set_password_and_dev_db 5433 studysync_dev

# ---------------------------------------------------------------------------
# 5. Elixir deps.
# ---------------------------------------------------------------------------
log "Fetching Elixir dependencies"
mix deps.get

log "Setup complete."
cat <<'EOF'

Next steps (run inside the repo):
  eval "$(mise activate bash)"     # if elixir isn't on PATH yet
  mix test                         # provisions the :5432 test DB and runs the suite
  mix ash.setup                    # (dev) set up the :5433 dev DB when running the app

DB facts (do not change these ports — they're committed in config/):
  test → localhost:5432  postgres/postgres  db studysync_test
  dev  → localhost:5433  postgres/postgres  db studysync_dev
EOF

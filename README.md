# railsctl

## Usage

```bash
railsctl <service> <command> [options]
railsctl <command> <service> [options]
railsctl config [service]
railsctl help
```

### Configured Services

Services are registered under `services/<service>/service.conf` (for example, `gallery`).

### Lifecycle & Deployment Commands

| Command | Description |
| :--- | :--- |
| `deploy` | Suspend service, create a quiescent SQLite backup, pull fast-forward (`--ff-only`), install gems, run migrations, precompile assets, resume service, and report status. |
| `start` | Start the systemd unit and verify the HTTP health check. |
| `stop` | Cleanly stop the systemd unit. |
| `suspend` | Enable Nginx `503` maintenance mode and stop Puma. |
| `resume` | Start Puma, verify the HTTP health check, and clear maintenance mode. |
| `backup` | Create a WAL-safe online SQLite backup and prune older snapshots beyond retention limits. |
| `test` | Run the isolated test suite against a temporary snapshot database. |
| `status` | Display systemd state, PID, memory, uptime, HTTP health, Git commit, and app version. |
| `version` | Display `railsctl` version, service app version constant, and Git SHA. |
| `config` | Display resolved configuration parameters for `<service>` or global `railsctl` settings. |
| `help` | Display usage syntax, configured services, and available commands. |

### `deploy` Options

| Option | Behavior |
| :--- | :--- |
| `--dry-run` | Run pre-flight checks and `git fetch`, display incoming commits, and exit without modifying code, database, or service state. |
| `--redeploy` | Execute the full 6-phase deployment pipeline even when `HEAD` already matches `<remote>/<branch>`. |
| `--no-backup` | Skip the quiescent SQLite snapshot step after suspending the service. |

### Examples

```bash
# Preview incoming commits without modifying the running service
railsctl gallery deploy --dry-run

# Deploy new commits from the configured remote branch
railsctl gallery deploy

# Force a full redeploy on the current commit without creating a new backup
railsctl gallery deploy --redeploy --no-backup

# Inspect runtime status and resolved configuration
railsctl gallery status
railsctl config gallery
```

## Project Summary & Proposal

### Objective
Develop `railsctl` — a set of Bash scripts to enable automated deployment and lifecycle handling for the `GALLERY` server on `uwanda` (similar in abilities to render.com or legacy heroku.com).

Parameterize everything (no magic numbers or literals); the same scripts will manage additional Ruby on Rails services on `uwanda` (such as `GALLERY-VIEWER` in the future).

Develop the scripts incrementally—testing every operation manually and individually on `uwanda` before incorporating it into a script.

---

## Project Objectives & Structural Agreement

### 1. Objective
Implement a parameterized, modular Bash deployment and lifecycle-management suite (`railsctl`) housed in a single Git/GitHub repository at `$HOME/railsctl/` to manage `GALLERY`—and future Ruby on Rails services such as `GALLERY-VIEWER`—on `uwanda`.

### 2. Repository & Filesystem Structure
All `railsctl` executables, configurations, and operational logs reside strictly within `$HOME`:

* **Git Repository Root:** `$HOME/railsctl/` (synced with GitHub `dsaronin/railsctl`)
  * `$HOME/railsctl/bin/railsctl` — Main dispatcher (`railsctl <service> <command> [args...]` and `railsctl <command> [service] [args...]`) routing to command sub-scripts.
  * `$HOME/railsctl/bin/railsctl.d/<command>` — Standalone executable Bash script per command.
  * `$HOME/railsctl/.config/railsctl.conf` — Global parameters (`railsctl` suite version, default HTTP health-check timeout, base directory paths).
  * `$HOME/railsctl/.config/<service>.conf` — Service-specific parameters (service user/group, `systemd` unit name, Nginx site/maintenance flag path, application directory, `.env` file path, SQLite backup directory and retention count, Git branch, Ruby wrapper directory, health-check endpoint, test runner path, and Ruby version constant).
  * `$HOME/railsctl/services/<service>/` — Per-service `railsctl` operational logs and state files (`.gitignored`).
* **PATH Symlink:** `$HOME/bin/railsctl -> $HOME/railsctl/bin/railsctl`
* **Service Runtime Logs:** Remain inside each service user's own directory tree (e.g., `/home/gallery/log`).

### 3. Architectural & Engineering Principles
* **Zero Magic Numbers or Hardcoded Literals:** All paths, Linux users/groups, Git branches, timeouts, retention thresholds, ports, and unit names live in `.conf` files.
* **Incremental Manual Validation:** Each command's operational mechanics are executed and verified manually step-by-step on `uwanda` before being written into `$HOME/railsctl/bin/railsctl.d/`.
* **Strict Privilege Boundaries:** `<USER>` executes `railsctl`; Git, Bundler, Rails, and SQLite commands drop privileges via `sudo -u "$SERVICE_USER"`; privileged service actions use standard password-prompted `sudo` for `systemd` units and Nginx reloads.

### 4. Phase 4 Command Set (v1 Scope — `ROLLBACK` Deferred)

| Command | Operational Behavior |
| :--- | :--- |
| **DEPLOY** | Runs an online SQLite `.backup` -> `git fetch` & `git pull --ff-only origin $GIT_BRANCH` -> `bundle install` (excluding `development`/`test`) -> `db:migrate` -> `assets:precompile` -> `systemctl restart` -> HTTP health check, printing `journalctl` diagnostics and exiting non-zero on failure. |
| **START** | Starts the currently installed release (`systemctl start`) and verifies the HTTP health check (does not pull code or recompile assets). |
| **STOP** | Cleanly stops the `systemd` unit (`systemctl stop`). |
| **SUSPEND** | Activates maintenance mode (creates maintenance flag so Nginx serves a clean `503 Service Unavailable` response instead of `502 Bad Gateway`) and stops Puma (`systemctl stop`). |
| **RESUME** | Starts Puma (`systemctl start`), verifies the HTTP health check passes, and clears the maintenance flag so Nginx resumes normal proxying. |
| **BACKUP** | Executes a WAL-safe online `sqlite3 .backup` into `$BACKUP_DIR` with timestamped filename, `0640` permissions, and retention pruning per service configuration. |
| **TEST** | Executes the service's isolated test suite runner against a temporary snapshot database and forwards its exit code. |
| **STATUS** | Displays `systemd` active/maintenance state, PID, memory usage, uptime since start, deployed Git commit SHA/branch, and live Ruby application version. |
| **VERSION** | Displays the `railsctl` suite version alongside the target service's (or all configured services') application version constant and Git commit SHA. |
| **CONFIG** | Lists resolved configuration parameters for `<service>` (or global `railsctl.conf`). |
| **HELP** | Displays command syntax, available configured services, and command descriptions. |

### 5. Exit Gate
1. Each command's mechanics are verified individually by hand on `uwanda` before scripting.
2. `$HOME/railsctl/` is initialized as a Git repository and pushed to GitHub (`dsaronin/railsctl`), with `$HOME/bin/railsctl` symlinked.
3. Pushing a test commit from `jabari` to GitHub (`main`) and executing `railsctl gallery deploy` on `uwanda` creates a pre-deploy SQLite backup, fast-forwards the repository, updates gems/migrations/assets, restarts `gallery.service`, logs the run under `$HOME/railsctl/services/gallery/`, and passes the post-restart HTTP health check.

---

## Implementation Plan (`railsctl` v1.0)

### Locked-In Design Parameters
* **Repository & Layout:** Single Git repository at `$HOME/railsctl/` (synced via SSH to GitHub `dsaronin/railsctl`), symlinked at `$HOME/bin/railsctl`. All `railsctl` files, configs, and operational logs stay strictly under `$HOME/`.
* **Privilege Escalation:** Standard password-prompted `sudo` (no custom `/etc/sudoers.d/` files).
* **Maintenance Mode (`SUSPEND` / `RESUME`):** Nginx returns `503 Service Unavailable` when the service's maintenance flag exists, serving an optional custom `/home/<service>/app/public/maintenance.html` if present, or a plain `503` response otherwise.
* **Backup Retention (`BACKUP`):** Retain the 10 most recent timestamped SQLite backups per service (configured via `.conf`), pruning older snapshots.
* **Discipline:** Every command's underlying mechanics are executed and verified manually on `uwanda` before being codified into `$HOME/railsctl/`.

### Stage 4.1: Repository Scaffold, Configuration & Dispatcher (`HELP`, `CONFIG`)
1. Initialize the Git repository at `$HOME/railsctl/` with `.gitignore` (excluding `services/` runtime logs/state), `README.md`, `bin/railsctl.d/`, `.config/`, and `services/gallery/`.
2. Connect the repository via SSH to GitHub (`git@github.com:dsaronin/railsctl.git`) and create the symlink `$HOME/bin/railsctl -> $HOME/railsctl/bin/railsctl`.
3. Create `.config/railsctl.conf` (global defaults) and `.config/gallery.conf` (all service-specific parameters, including `BACKUP_RETENTION=10`, zero hardcoded literals).
4. Build the shared helper library (`bin/railsctl.d/_common.sh`) for config resolution, logging to `$HOME/railsctl/services/<service>/`, and standardized output.
5. Build and verify the dispatcher and initial read-only commands in three discrete sub-steps:
   1. **Skeleton Dispatcher:** Implement `$HOME/railsctl/bin/railsctl` so it resolves its physical path, parses arguments, and returns cleanly.
   2. **HELP:** Implement and verify `bin/railsctl.d/help` (lists syntax, configured services, and command descriptions).
   3. **CONFIG (Read-Only):** Implement and verify `bin/railsctl.d/config` to list resolved parameters for `<service>` or global `railsctl.conf`. *(In-place parameter editing via `CONFIG` is deferred to a future version; edits are made manually in `gvim`/`vim`.)*

### Stage 4.2: Service Introspection (`VERSION`, `STATUS`)
1. Manually test `systemctl show` property extraction (active state, PID, memory footprint, `ActiveEnterTimestamp`), Git branch/commit SHA lookup, and Ruby constant evaluation (`Gallery::VERSION`) via `sudo -u "$SERVICE_USER"`.
2. Codify and verify `bin/railsctl.d/version` and `bin/railsctl.d/status` (including maintenance-flag detection).

### Stage 4.3: Online Backup & Isolated Testing (`BACKUP`, `TEST`)
1. Manually test WAL-safe `sqlite3 .backup` into `/home/gallery/backups/`, `0640` permission enforcement, and retention pruning keeping the 10 newest snapshots.
2. Codify and verify `bin/railsctl.d/backup`.
3. Parameterize the existing `~/bin/gallery-test` workflow (fixture copy to `/tmp`, migration, `./script/run_all_tests.sh`, trap cleanup) into `bin/railsctl.d/test` and verify exit-code propagation.

### Stage 4.4: Lifecycle Control & Maintenance Mode (`START`, `STOP`, `SUSPEND`, `RESUME`)
1. Manually test `systemctl stop` and `systemctl start` paired with a parameterized HTTP health check (`curl` against `BIND` + `HEALTH_PATH`).
2. Update `/etc/nginx/sites-available/gallery.conf` to check for the service's maintenance flag file and serve `503` (rendering `/home/gallery/app/public/maintenance.html` if present, otherwise a plain `503` response); manually verify `200 -> 503 -> 200` transitions both with and without `maintenance.html`.
3. Codify and verify `bin/railsctl.d/stop`, `start`, `suspend`, and `resume`.

### Stage 4.5: Automated Deployment Pipeline (`DEPLOY`) & Exit Gate
1. Manually step through the full `DEPLOY` sequence (`backup` -> `git fetch` & `git pull --ff-only` -> `bundle install` -> `db:migrate` -> `assets:precompile` -> `systemctl restart` -> HTTP health check + `journalctl` failure dump).
2. Codify `bin/railsctl.d/deploy` (reusing `backup` and shared health-check helpers) with fail-fast error handling (`set -euo pipefail`) and deployment logging under `$HOME/railsctl/services/gallery/`.
3. **Exit Gate:** Push a test commit from `jabari` to `dsaronin/gallery` (`main`), execute `railsctl gallery deploy` on `uwanda`, and verify pre-deploy backup creation, code fast-forward, restart, log entry, and passing health check.
4. Commit and push `railsctl` v1.0 to `git@github.com:dsaronin/railsctl.git`.

## Service Provisioning (`railsctl init`)

`railsctl init <service>` performs one-time, full-stack provisioning of a new Ruby on Rails service on the host using interactive prompts with sensible defaults. Provisioning stops once the service skeleton is in place and verified, leaving first-time dependency installation, database migration, asset precompilation, and startup to `railsctl <service> deploy`.

```bash
railsctl init <service> [--dry-run]
```

### Architectural Guarantees

* **Dedicated Templates (`templates/`):** Configuration files (`service.conf.tmpl`, `service.env.tmpl`, `systemd.service.tmpl`, `nginx.conf.tmpl`) use `@@TOKEN@@` placeholders so Nginx variables (`$uri`, `$http_host`, `$scheme`) are never altered during rendering. * **Built-In Pre-Flight Dry-Run Gate:** Every invocation executes a read-only dry-run pass first—validating inputs, checking system/port collisions, testing Git remote reachability, and verifying template rendering—before requesting `y/N` confirmation. Passing `--dry-run` runs this identical pass, prints the planned actions, and exits `0` without modifying the system. * **Per-Phase Validation:** Every mutating phase (Phases 2–5) ends with a dedicated verification step (skipped under `--dry-run`). Any validation failure halts execution and triggers rollback. * **Clean Reverse-Order Rollback:** `init` tracks only artifacts created during the current invocation (`CREATED_GROUP`, `CREATED_USER`, `ADDED_GROUP_MEMBERS`, `CREATED_HOME`, `CREATED_CONF`, `CREATED_LOG_DIR`, `CREATED_SYSTEMD`, `CREATED_NGINX_AVAIL`, `CREATED_NGINX_ENABLED`). On catastrophic error or failed validation, rollback executes in strict reverse order (Nginx -> Systemd -> `railsctl` config/logs -> `/home/<service>` -> group memberships -> newly created user/group) without touching pre-existing shared resources.  ---  ### Provisioning Phases  #### Phase 1 — Validation, Interactive Prompting & Dry-Run Gate  * **Scope:** * Validate `<service>` naming syntax (`^[a-z][a-z0-9_-]*$`).
  * Prompt interactively with defaults for Display Name, Git Repository URL (required), Git Branch (`main`), System User (`<service>`), System Group (`<service>`), Puma Port, Nginx Port, Ruby Wrapper Directory (`/usr/local/rvm/wrappers/ruby-3.3.11`), Version Constant, and Version File.
  * Run pre-flight collision checks against `.config/<service>.conf`, `/home/<service>`, `/etc/systemd/system/<service>.service`, `/etc/nginx/sites-available/<service>.conf`, active sockets (`ss`), existing Nginx site ports, Ruby wrapper availability, and Git remote reachability (`git ls-remote`).
  * Display the resolved summary and require `y/N` confirmation (or exit `0` if `--dry-run` is active).
* **Validation:** Confirms all four templates exist and render into temporary buffers with zero unresolved `@@TOKEN@@` markers.

#### Phase 2 — OS User, Group & Directory Skeleton

* **Scope:**
  * Create the system group if absent and create the system user (`--system --home-dir /home/<service> --shell /usr/sbin/nologin`).
  * Add `www-data` and the invoking operator to `<service_group>`; add `<service_user>` to the `rvm` group.
  * Provision `/home/<service>` (`0750`), `app` (`0755`), `data` (`0750`), `config` (`0700`), and `backups` (`0750`) with strict ownership.
* **Validation:** Verifies user (`id`), group (`getent group`), group memberships, and exact directory ownership/octal modes (`stat`).
* **Rollback:** Removes `/home/<service>`, strips group memberships added during the run, deletes `<service_user>`, and deletes `<service_group>` if newly created.

#### Phase 3 — Repository Clone, Maintenance Flag & Environment File

* **Scope:**
  * Clone the Git repository into `/home/<service>/app` as `<service_user>` on the configured branch.
  * Create `app/tmp/pids` (`0775`) and `app/tmp/maintenance.flag` so Nginx serves `HTTP 503` until the first `deploy` completes.
  * Generate a 128-character hex `SECRET_KEY_BASE` via Ruby `SecureRandom` and render `/home/<service>/config/<service>.env` (`0600`) from `service.env.tmpl`.
* **Validation:** Verifies a valid Git worktree on the target branch, presence of `maintenance.flag`, `<service>.env` mode `0600` readable by `<service_user>`, and a non-empty `SECRET_KEY_BASE`.
* **Rollback:** Reverted cleanly via Phase 2 `/home/<service>` removal.

#### Phase 4 — `railsctl` Configuration Registration & Audit Logging

* **Scope:**
  * Render `.config/<service>.conf` (`0644`) from `service.conf.tmpl`.
  * Create `services/<service>/` and record `INIT` entries in `services/<service>/railsctl.log`.
* **Validation:** Runs `bash -n` on `.config/<service>.conf`, confirms `railsctl config <service>` exits `0`, and confirms `railsctl.log` is writable.
* **Rollback:** Removes `.config/<service>.conf` and `services/<service>/`.

#### Phase 5 — Systemd Unit, Nginx Reverse Proxy & Handoff

* **Scope:**
  * Render `/etc/systemd/system/<service>.service` (`0644`), run `systemctl daemon-reload`, and enable `<service>.service` (leaving the unit stopped for the first `deploy`).
  * Render `/etc/nginx/sites-available/<service>.conf` (`0644`), symlink into `/etc/nginx/sites-enabled/<service>.conf`, test with `nginx -t`, and reload Nginx.
  * Print post-init handoff instructions:
    1. Run `railsctl <service> deploy --redeploy --no-backup` to execute first-time `bundle install`, `db:migrate`, `assets:precompile`, service start, and health verification.
    2. Configure any required UFW firewall rules for `<nginx_port>`.
* **Validation:** Verifies `systemctl is-enabled <service>.service`, `systemd-analyze verify`, `nginx -t`, and confirms `http://127.0.0.1:<nginx_port>/` returns `HTTP 503`.
* **Rollback:** Removes the Nginx symlink and vhost, tests (`nginx -t`) and reloads Nginx; disables and removes the systemd unit and runs `systemctl daemon-reload`; then cascades through Phases 4, 3, and 2 rollback.


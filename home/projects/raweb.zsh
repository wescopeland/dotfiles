# RetroAchievements (RAWeb). The repo is at $RAWEB_DIR, which defaults to $GITHUB_DIR/RAWeb.

: "${RAWEB_DIR:=$GITHUB_DIR/RAWeb}"
: "${RA_BACKUP_REMOTE:=r2:backup/db-backup}"
: "${RA_BACKUP_AGE_KEY:=$HOME/.config/age/ra-db-backup.txt}"
WORKTREE_WORKSPACES+=("$RAWEB_DIR")

alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'
alias rascript='WINEDEBUG="-all" wine /Applications/RATools/rascript-cli.exe "${@/#-o\s+~/-o $HOME}"'
alias ra-db-pull='rclone copy "$RA_BACKUP_REMOTE/$(rclone lsf "$RA_BACKUP_REMOTE/" --files-only | sort | tail -1)" ~/Downloads/ -P --multi-thread-streams=8 --s3-chunk-size=64M'

function resync-ra-db() {
  setopt local_options err_return
  local raweb_dir="$RAWEB_DIR"
  local r2_prefix="$RA_BACKUP_REMOTE"

  print -P "%F{cyan}==> Finding latest backup in Cloudflare R2...%f"
  local latest_backup
  latest_backup=$(rclone lsf "$r2_prefix/" --files-only | sort | tail -1)
  if [[ -z "$latest_backup" ]]; then
    print -P "%F{red}No backups found in $r2_prefix. Aborting.%f"
    return 1
  fi
  print -P "%F{cyan}    Latest: $latest_backup%f"

  local backup_file="$HOME/Downloads/$latest_backup"
  if [[ -f "$backup_file" ]]; then
    print -P "%F{cyan}==> Already downloaded, skipping download.%f"
  else
    print -P "%F{cyan}==> Downloading from R2...%f"
    rclone copyto "$r2_prefix/$latest_backup" "$backup_file" \
      -P --multi-thread-streams=8 --s3-chunk-size=64M
  fi

  if [[ ! -f "$backup_file" ]]; then
    print -P "%F{red}Backup file not found at $backup_file. Aborting.%f"
    return 1
  fi

  # Backups uploaded since the switch to age are encrypted. Older ones are plain
  # .tar.zst files until they rotate out. Check the key before anything is wiped.
  local -a decrypt=(cat)
  if [[ "$backup_file" == *.age ]]; then
    if ! command -v age >/dev/null; then
      print -P "%F{red}age is not installed. Run: brew install age%f"
      return 1
    fi
    if [[ ! -f "$RA_BACKUP_AGE_KEY" ]]; then
      print -P "%F{red}No age key at $RA_BACKUP_AGE_KEY. Save the key from the password manager there, or set RA_BACKUP_AGE_KEY. Aborting.%f"
      return 1
    fi
    # age rejects a wrong key in the header, so one decrypted byte proves the key
    # works without reading the whole file.
    if (( $(age -d -i "$RA_BACKUP_AGE_KEY" "$backup_file" 2>/dev/null | head -c 1 | wc -c) != 1 )); then
      print -P "%F{red}The key at $RA_BACKUP_AGE_KEY cannot decrypt $latest_backup. Aborting.%f"
      return 1
    fi
    decrypt=(age -d -i "$RA_BACKUP_AGE_KEY")
  fi

  print -P "%F{cyan}==> Stopping Sail (in case it's running)...%f"
  (cd "$raweb_dir" && vendor/bin/sail down)

  print -P "%F{cyan}==> Wiping mariadb volume...%f"
  docker run --rm -v raweb_mariadb-data:/var/lib/mysql alpine \
    sh -c 'rm -rf /var/lib/mysql/* /var/lib/mysql/.[!.]* 2>/dev/null || true'

  print -P "%F{cyan}==> Streaming restore into volume...%f"
  # pipe_fail makes a wrong key or a corrupt file stop the function here, instead
  # of restoring an empty volume. The subshell keeps the option off elsewhere.
  (
    setopt pipe_fail
    pv "$backup_file" | "${decrypt[@]}" | zstd -dc | \
      docker run --rm -i \
        -v raweb_mariadb-data:/var/lib/mysql \
        mariadb:10 \
        bash -c 'tar -xf - --strip-components=1 -C /var/lib/mysql && rm -f /var/lib/mysql/xtrabackup_* /var/lib/mysql/backup-my.cnf && chown -R mysql:mysql /var/lib/mysql'
  )

  print -P "%F{cyan}==> Adding retroachievements@%% user (via skip-grant-tables)...%f"
  docker rm -f mariadb-fix >/dev/null 2>&1 || true
  docker run --rm -d --name mariadb-fix \
    -v raweb_mariadb-data:/var/lib/mysql \
    mariadb:10 --skip-grant-tables >/dev/null

  # This helper holds an exclusive lock on the data volume. If it survives an
  # early return or a Ctrl-C, the real db container cannot start at all.
  trap 'docker rm -f mariadb-fix >/dev/null 2>&1 || true' EXIT INT TERM

  # A freshly restored volume replays redo and rolls back open transactions
  # before it accepts connections, so allow several minutes here.
  local attempts=0 max_attempts=600
  until docker exec mariadb-fix mariadb -e "SELECT 1" >/dev/null 2>&1; do
    if ! docker inspect -f '{{.State.Running}}' mariadb-fix 2>/dev/null | grep -q true; then
      print -P "%F{red}mariadb-fix exited during startup. Aborting.%f"
      return 1
    fi
    sleep 1
    # Assignment, not (( attempts++ )): arithmetic that evaluates to 0 returns
    # status 1, which silently aborts the whole function under err_return.
    attempts=$(( attempts + 1 ))
    if (( attempts % 15 == 0 )); then
      print -P "%F{yellow}    still recovering... ${attempts}s%f"
    fi
    if (( attempts > max_attempts )); then
      print -P "%F{red}mariadb-fix never came up after ${max_attempts}s. Aborting.%f"
      return 1
    fi
  done

  docker exec mariadb-fix mariadb -e "
    FLUSH PRIVILEGES;
    CREATE USER IF NOT EXISTS 'retroachievements'@'%' IDENTIFIED BY 'retroachievements';
    GRANT ALL PRIVILEGES ON *.* TO 'retroachievements'@'%' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
  "

  # Production ships tens of GB of telemetry and failed-job rows that local
  # QA never reads. Dropping them here trims the local disk image before Sail
  # boots. TRUNCATE rebuilds each .ibd file, so the space returns at once.
  print -P "%F{cyan}==> Truncating large tables local QA does not need...%f"
  docker exec mariadb-fix mariadb -e "
    TRUNCATE TABLE retroachievements.pulse_entries;
    TRUNCATE TABLE retroachievements.pulse_aggregates;
    TRUNCATE TABLE retroachievements.pulse_values;
    TRUNCATE TABLE retroachievements.queue_failed_jobs;
  "

  docker stop mariadb-fix >/dev/null
  # Wait for the lock to be released before Sail's mariadb claims the volume.
  while docker inspect mariadb-fix >/dev/null 2>&1; do
    sleep 1
  done
  trap - EXIT INT TERM

  print -P "%F{cyan}==> Starting Sail back up...%f"
  (cd "$raweb_dir" && vendor/bin/sail up -d)

  print -P "%F{green}==> Restore complete.%f"
}

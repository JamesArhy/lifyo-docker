# Life is Feudal: Your Own — Docker (Linux)

Run the Windows-only LiF:YO dedicated server on a Linux host using Docker,
Wine, and Xvfb. All common server settings are configurable via environment
variables — no need to hand-edit XML files.

## Architecture

```
┌─────────────────────────────────┐
│  docker-compose                 │
│                                 │
│  ┌───────────┐   ┌───────────┐ │
│  │  mariadb   │◄──│  lif-yo   │ │
│  │  (10.6)    │   │ Wine+Xvfb │ │
│  └─────┬─────┘   └─────┬─────┘ │
│        │               │       │
│   vol: data        vol: server │
└────────┼───────────────┼───────┘
         │               │
    Port 3306       Port 28000
   (optional)       UDP + TCP
```

**lif-yo container:**
- Ubuntu 22.04 base
- WineHQ (stable) to run the Windows server binary
- Xvfb (virtual framebuffer) so Wine doesn't need a display
- SteamCMD to download/update AppID 320850
- VC++ 2015 runtime via winetricks
- `envsubst` templating generates `config_local.cs` and `world_N.xml` at startup

**mariadb container:**
- MariaDB 10.6 with LiF-required InnoDB settings
- Database auto-created on first start

## Quick Start

```bash
# 1. Clone / copy this directory to your server
# 2. Create your .env file
cp .env.example .env
# Edit .env — change passwords, server name, tweak settings

# 3. Build & start
docker compose build        # First build takes ~10-15 min (downloads Wine + game)
docker compose up -d

# 4. Watch logs
docker compose logs -f lif-yo
```

The server is ready when you see `Steam Initialized.` in the logs.

## Environment Variables

All settings are configured through environment variables in `.env` or
`docker-compose.yml`. The entrypoint generates `config_local.cs` and
`world_N.xml` from these on every container start.

### Database

| Variable           | Default        | Description                              |
|--------------------|----------------|------------------------------------------|
| `DB_ROOT_PASSWORD` | `rootChangeme` | MariaDB root password                    |
| `DB_NAME`          | `lif_1`        | Database name                            |
| `DB_USER`          | `lif`          | Database user                            |
| `DB_PASSWORD`      | `changeme`     | Database password                        |

### Server Identity

| Variable         | Default                            | Description                                    |
|------------------|------------------------------------|------------------------------------------------|
| `SERVER_NAME`    | `Life is Feudal Docker Server`     | Name shown in the server browser (max 63 chars)|
| `SERVER_PASSWORD`| *(empty)*                          | Password to join (blank = open)                |
| `ADMIN_PASSWORD` | *(empty)*                          | GM password (blank = GM disabled)              |
| `GAME_MODE`      | `Sandbox`                          | `Sandbox` or `PermaDeath`                      |
| `IS_PRIVATE`     | `0`                                | `1` = hidden from server browser               |
| `GAME_PORT`      | `28000`                            | Game port (UDP + TCP)                          |
| `WORLD_ID`       | `1`                                | World ID (matches world_N.xml)                 |
| `MAX_PLAYERS`    | `64`                               | Max simultaneous players (1–64)                |

### Skills & Progression

| Variable             | Default | Range       | Description                                      |
|----------------------|---------|-------------|--------------------------------------------------|
| `SKILLS_MULTIPLIER`  | `10`    | 0.1–100     | XP rate multiplier (1 = vanilla MMO rate)        |
| `CRAFTING_SKILLCAP`  | `600`   | 200–3000    | Crafting skills group cap (600 = vanilla)        |
| `COMBAT_SKILLCAP`    | `400`   | 200–3000    | Combat skills group cap (400 = vanilla)          |
| `MINOR_SKILLCAP`     | `400`   | 200–3000    | Minor skills group cap (400 = vanilla)           |

### World Simulation

| Variable              | Default | Range     | Description                                          |
|-----------------------|---------|-----------|------------------------------------------------------|
| `OBJECT_DECAY_RATE`   | `0`     | 0+        | Building decay rate (0 = disabled)                   |
| `TERRAFORMING_SPEED`  | `4`     | 0.1–60    | Tunneling speed (0.8 = vanilla)                      |
| `CRAFTING_PERIOD`     | `60`    | 1–3600    | Seconds per crafting tick (fuel burn, heating, etc.)  |
| `ANIMAL_BREED_PERIOD` | `60`    | 1–600     | Minutes between breeding checks                      |
| `DAY_CYCLE`           | `3`     | 0.5–24    | Real-life hours per in-game day                      |
| `ANIMALS_COUNT`       | `100`   | 0–100     | Animal spawn points (higher = more CPU)              |

### Miscellaneous

| Variable                        | Default | Description                                   |
|---------------------------------|---------|-----------------------------------------------|
| `MOVABLE_MAX_DROP_HEIGHT`       | `5`     | Max drop height in meters for movable objects |
| `RANDOM_EVENT_CHANCE_WALKING`   | `0.03`  | Chance of random event while walking          |
| `RANDOM_EVENT_CHANCE_ABILITY`   | `0.02`  | Chance of random event while using abilities  |
| `HORSE_DECAY`                   | `90.00` | Hours before unattended horses despawn        |
| `DROP_ON_PRAY`                  | `0`     | `1` = drop inventory when using homecoming    |

### Judgement Hour (Guild Warfare)

| Variable        | Default | Description                            |
|-----------------|---------|----------------------------------------|
| `JH_ENABLED`    | `0`     | `1` = enable Judgement Hour            |
| `JH_START_TIME` | `18:00` | Start time (HH:MM)                    |
| `JH_MON`–`JH_SUN` | `0`  | `1` = Judgement active on that day     |

### Maintenance

| Variable          | Default | Description                                  |
|-------------------|---------|----------------------------------------------|
| `UPDATE_ON_START` | `false` | `true` = run SteamCMD update on each start   |

## How Templating Works

The entrypoint uses `envsubst` to substitute `${VAR}` placeholders in two
template files:

1. `config_local.cs.template` → `config_local.cs` (database connection)
2. `world_1.xml.template` → `config/world_N.xml` (all game settings)

This happens **on every container start**, so changing a variable in `.env` and
restarting the container immediately applies the new settings. No need to shell
in and edit files.

If you need settings that aren't exposed as env vars, you can either edit the
template files or mount your own `world_1.xml` directly:

```yaml
volumes:
  - ./my-world_1.xml:/home/lif/yoserver/config/world_1.xml:ro
```

(This bypasses the templating for that file.)

## Firewall / Port Forwarding

Open **UDP and TCP port 28000** (or whatever `GAME_PORT` is set to) plus ports
+1 and +2 (28001, 28002) on your host firewall and any upstream router or
cloud security group.

## Updating the Server

**Option A** — set `UPDATE_ON_START=true` in `.env` and restart:
```bash
docker compose restart lif-yo
```

**Option B** — manual one-off update:
```bash
docker compose exec lif-yo su - lif -c \
  "/home/lif/steamcmd/steamcmd.sh \
   +@sSteamCmdForcePlatformType windows \
   +login anonymous \
   +force_install_dir /home/lif/yoserver \
   +app_update 320850 validate +quit"
docker compose restart lif-yo
```

## Backups

The important data lives in Docker volumes:

- **mariadb_data** — the database (character data, world state)
- **lif_server** — full server directory (configs, mods, saves)

```bash
# Database dump
docker compose exec mariadb mysqldump -u root -p"${DB_ROOT_PASSWORD}" lif_1 > backup.sql

# File backup
docker run --rm -v lif-yo-docker_lif_server:/data -v $(pwd):/backup \
  alpine tar czf /backup/lif-server-backup.tar.gz -C /data .
```

## Troubleshooting

**Server crashes immediately** — Check `docker compose logs lif-yo` for Wine
errors. Verify MariaDB health with `docker compose ps`. The VC++ 2015 runtime
must install correctly during the Docker build.

**Cannot connect from game client** — Confirm ports 28000–28002 UDP+TCP are
open. Wait at least 5 minutes after first start for Steam registration. Verify
`SERVER_NAME` is set and `IS_PRIVATE` is `0`.

**Database errors (#2006 MySQL gone away)** — Try increasing `max_allowed_packet`
in `mariadb-custom.cnf`. Verify `DB_HOST`, `DB_USER`, `DB_PASSWORD` match.

**Settings not taking effect** — The world XML is regenerated on every start.
Make sure you're editing `.env` (not the XML directly inside the container) and
restarting with `docker compose restart lif-yo`.

## Files

```
├── .env.example              # All settings with defaults & documentation
├── .dockerignore
├── Dockerfile                # Ubuntu 22.04 + Wine + SteamCMD + game server
├── docker-compose.yml        # Orchestrates MariaDB + LiF server
├── entrypoint.sh             # Generates configs from env vars & launches server
├── config_local.cs.template  # DB connection template
├── world_1.xml.template      # World settings template (all env var placeholders)
├── mariadb-custom.cnf        # Required MariaDB InnoDB settings
└── README.md
```

## Credits

Based on community guides from
[FeudalTools](https://kb.feudal.tools/),
[LiF Forums](https://lifeisfeudal.com/forum/), and
[LiFx Extended](https://lifxmod.com/).

// cm_skill_config.cs — Client-side override for modified skill parent thresholds.
//
// Installation:
//   Copy this file to your game client folder:
//   <Steam>/steamapps/common/Life is Feudal Your Own/scripts/server/cm_skill_config.cs
//
//   The .cs source file takes precedence over the compiled .cs.dso,
//   so placing it alongside the existing cm_skill_config.cs.dso overrides it.
//
// These values MUST match the server's SKILL_PARENT_MODE setting.
// This file uses the "lowered" thresholds (0/10/30/45/60/100).

// ── Parent skill level required to unlock each child tier ──────────────────
$cm_skill_config::skill_level::none = 0;
$cm_skill_config::skill_level::novice = 10;
$cm_skill_config::skill_level::apprentice = 30;
$cm_skill_config::skill_level::expert = 45;
$cm_skill_config::skill_level::master = 60;
$cm_skill_config::skill_level::grandmaster = 100;

// ── Skill growth rate thresholds (vanilla, unchanged) ──────────────────────
$cm_skill_config::skillgrow::none = 200;
$cm_skill_config::skillgrow::novice = 500;
$cm_skill_config::skillgrow::apprentice = 2500;
$cm_skill_config::skillgrow::expert = 12500;
$cm_skill_config::skillgrow::master = 125000;
$cm_skill_config::skillgrow::grandmaster = 0;

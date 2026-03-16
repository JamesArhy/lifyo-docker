// cm_skill_config.cs — Client-side override for REMOVED skill parent thresholds.
//
// Installation:
//   Rename this file to cm_skill_config.cs and copy to:
//   <Steam>/steamapps/common/Life is Feudal Your Own/scripts/server/cm_skill_config.cs
//
// Use this file when the server's SKILL_PARENT_MODE is set to "none".

// ── Parent skill level required to unlock each child tier (all zeroed) ─────
$cm_skill_config::skill_level::none = 0;
$cm_skill_config::skill_level::novice = 0;
$cm_skill_config::skill_level::apprentice = 0;
$cm_skill_config::skill_level::expert = 0;
$cm_skill_config::skill_level::master = 0;
$cm_skill_config::skill_level::grandmaster = 0;

// ── Skill growth rate thresholds (vanilla, unchanged) ──────────────────────
$cm_skill_config::skillgrow::none = 200;
$cm_skill_config::skillgrow::novice = 500;
$cm_skill_config::skillgrow::apprentice = 2500;
$cm_skill_config::skillgrow::expert = 12500;
$cm_skill_config::skillgrow::master = 125000;
$cm_skill_config::skillgrow::grandmaster = 0;

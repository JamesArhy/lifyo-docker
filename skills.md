# Life is Feudal: Your Own — Skill Reference

## Skill Tree

| ID | Name | Parent | Primary | Secondary |
|----|------|--------|---------|-----------|
| 1 | Artisan | (root) | Int | Str |
| 2 | Mining | Digging | Str | Con |
| 3 | Smelting | Materials Preparation | Agi | Int |
| 4 | Forging | Smelting | Str | Con |
| 5 | Armorsmithing | Smelting | Str | Agi |
| 6 | Forestry | Farming | Con | Will |
| 7 | Building Maintain | Masonry | Str | Con |
| 8 | Carpentry | Artisan | Con | Str |
| 9 | Bowcraft | Carpentry | Con | Will |
| 10 | Warfare engineering | Bowcraft | Will | Int |
| 11 | Nature's lore | (root) | Int | Will |
| 12 | Herbalism | Nature's lore | Will | Con |
| 13 | Brewing | Advanced Farming | Agi | Int |
| 14 | Healing | Herbalism | Int | Str |
| 15 | Alchemy | Healing | Int | Agi |
| 16 | Digging | Artisan | Con | Str |
| 17 | Materials Preparation | Artisan | Will | Agi |
| 18 | Construction | Artisan | Will | Agi |
| 19 | Masonry | Construction | Con | Str |
| 20 | Architecture | Masonry | Will | Int |
| 21 | Farming | Nature's lore | Agi | Will |
| 22 | Animal lore | Hunting | Int | Will |
| 23 | Procuration | Animal lore | Str | Agi |
| 24 | Cooking | Advanced Farming | Agi | Con |
| 25 | Tailoring | Procuration | Agi | Int |
| 26 | Warhorse training | Procuration | Int | Will |
| 28 | Cavalryman | (root) | Str | Int |
| 29 | Knight | Cavalryman | Con | Str |
| 30 | Lancer | Knight | Int | Agi |
| 31 | Precious Prospecting | Mining | Will | Agi |
| 32 | Advanced Farming | Farming | Will | Con |
| 33 | Militia | (root) | Agi | Will |
| 34 | Spearman | Militia | Will | Str |
| 35 | Guard | Spearman | Int | Str |
| 36 | Footman | (root) | Con | Agi |
| 38 | Swordsman | Footman | Will | Con |
| 40 | Huscarl | Swordsman | Str | Will |
| 43 | Assaulter | (root) | Agi | Str |
| 44 | Vanguard | Assaulter | Str | Con |
| 45 | Berserk | Vanguard | Con | Will |
| 47 | Slinger | (root) | Agi | Int |
| 48 | Archer | Slinger | Str | Agi |
| 49 | Ranger | Archer | Int | Will |
| 51 | Hunting | (root) | Str | Agi |
| 52 | Jewelry | Mining | Agi | Con |
| 53 | Arts | (root) | Con | Will |
| 54 | Piety | (root) | Will | Int |
| 55 | Mentoring | (root) | Int | Str |
| 56 | Unit and formation | (root) | Int | Con |
| 57 | Equipment maintain | (root) | Con | Int |
| 58 | Battle Survival | (root) | Agi | Con |
| 59 | Demolition | (root) | Will | Agi |
| 61 | Movement | (root) | Str | Will |
| 62 | General actions | (root) | Con | Str |
| 63 | Horseback riding | (root) | Agi | Int |
| 64 | Swimming | (root) | Will | Agi |
| 65 | Authority | (root) | Int | Con |

### Crafting Chains

- **Artisan** -> Carpentry -> Bowcraft -> Warfare engineering
- **Artisan** -> Construction -> Masonry -> Architecture / Building Maintain
- **Artisan** -> Materials Preparation -> Smelting -> Forging / Armorsmithing
- **Artisan** -> Digging -> Mining -> Precious Prospecting / Jewelry
- **Nature's lore** -> Farming -> Advanced Farming -> Cooking / Brewing
- **Nature's lore** -> Herbalism -> Healing -> Alchemy
- **Hunting** -> Animal lore -> Procuration -> Tailoring / Warhorse training

### Combat Chains

- **Cavalryman** -> Knight -> Lancer
- **Militia** -> Spearman -> Guard
- **Footman** -> Swordsman -> Huscarl
- **Assaulter** -> Vanguard -> Berserk
- **Slinger** -> Archer -> Ranger

## Admin SQL Commands

Run from within the lif-yo container using the environment variables already
set by the entrypoint:

```bash
mysql -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}"
```

### Find a character's ID by name

```sql
SELECT ID, Name FROM `character`;
```

### Set a specific skill to a specific level

SkillAmount uses a 0-1,000,000,000 scale where 10,000,000 = 1 displayed level
(so level 60 = 600,000,000 and level 100 = 1,000,000,000).

```sql
-- Set Artisan (ID 1) to level 60 for character ID 1
UPDATE skills SET SkillAmount = 600000000
WHERE CharacterID = 1 AND SkillTypeID = 1;
```

### Set a skill by name

```sql
-- Set Construction to level 30 for a character named "Jamie"
UPDATE skills s
JOIN `character` c ON s.CharacterID = c.ID
JOIN skill_type st ON s.SkillTypeID = st.ID
SET s.SkillAmount = 300000000
WHERE c.Name = 'Jamie' AND st.Name = 'Construction';
```

### Boost all crafting parent skills for a character

Useful to unblock the skill tree without grinding parent skills.

```sql
-- Set Artisan, Nature's lore, and Hunting to level 60 for character ID 1
UPDATE skills SET SkillAmount = 600000000
WHERE CharacterID = 1 AND SkillTypeID IN (1, 11, 51);
```

### Set all skills to a level for a character

```sql
-- Set every skill to level 30 for character ID 1
UPDATE skills SET SkillAmount = 300000000
WHERE CharacterID = 1;
```

### View a character's current skills

```sql
SELECT st.ID, st.Name, s.SkillAmount,
       ROUND(s.SkillAmount / 10000000, 1) AS Level
FROM skills s
JOIN skill_type st ON s.SkillTypeID = st.ID
WHERE s.CharacterID = 1
  AND s.SkillAmount > 0
ORDER BY s.SkillAmount DESC;
```

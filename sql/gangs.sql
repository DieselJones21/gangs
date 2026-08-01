CREATE TABLE IF NOT EXISTS `gangs_organizations` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(64) NOT NULL,
    `label` VARCHAR(128) NOT NULL,
    `color` VARCHAR(16) NOT NULL DEFAULT '#DE2A21',
    `owner` VARCHAR(64) NOT NULL,
    `power` INT NOT NULL DEFAULT 0,
    `bank` INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_gangs_org_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gangs_roles` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `org_id` INT NOT NULL,
    `name` VARCHAR(64) NOT NULL,
    `grade` INT NOT NULL DEFAULT 0,
    `permissions` LONGTEXT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_gangs_roles_org` (`org_id`),
    CONSTRAINT `fk_gangs_roles_org` FOREIGN KEY (`org_id`) REFERENCES `gangs_organizations` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gangs_members` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `org_id` INT NOT NULL,
    `identifier` VARCHAR(64) NOT NULL,
    `citizenid` VARCHAR(64) DEFAULT NULL,
    `name` VARCHAR(128) NOT NULL,
    `role_id` INT NOT NULL,
    `joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_gangs_member` (`identifier`),
    KEY `idx_gangs_members_org` (`org_id`),
    CONSTRAINT `fk_gangs_members_org` FOREIGN KEY (`org_id`) REFERENCES `gangs_organizations` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gangs_zones` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `zone_key` VARCHAR(64) NOT NULL,
    `title` VARCHAR(128) NOT NULL,
    `type` VARCHAR(32) NOT NULL,
    `owner_org` VARCHAR(64) DEFAULT NULL,
    `points` LONGTEXT NOT NULL,
    `center_x` FLOAT NOT NULL DEFAULT 0,
    `center_y` FLOAT NOT NULL DEFAULT 0,
    `center_z` FLOAT NOT NULL DEFAULT 0,
    `min_z` FLOAT DEFAULT NULL,
    `max_z` FLOAT DEFAULT NULL,
    `protection` INT NOT NULL DEFAULT 0,
    `npc_count` INT NOT NULL DEFAULT 0,
    `street_rep` INT NOT NULL DEFAULT 0,
    `data` LONGTEXT NOT NULL,
    `cooldown_until` BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_gangs_zone_key` (`zone_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gangs_bounties` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `target_identifier` VARCHAR(64) NOT NULL,
    `target_name` VARCHAR(128) NOT NULL,
    `placer_identifier` VARCHAR(64) NOT NULL,
    `placer_name` VARCHAR(128) NOT NULL,
    `org_name` VARCHAR(64) DEFAULT NULL,
    `amount` INT NOT NULL,
    `reason` VARCHAR(255) DEFAULT NULL,
    `active` TINYINT(1) NOT NULL DEFAULT 1,
    `claimed_by` VARCHAR(64) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_gangs_bounties_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gangs_stats` (
    `identifier` VARCHAR(64) NOT NULL,
    `citizenid` VARCHAR(64) DEFAULT NULL,
    `name` VARCHAR(128) NOT NULL,
    `kills` INT NOT NULL DEFAULT 0,
    `headshots` INT NOT NULL DEFAULT 0,
    `captured` INT NOT NULL DEFAULT 0,
    `bounties` INT NOT NULL DEFAULT 0,
    `wars_won` INT NOT NULL DEFAULT 0,
    `robberies` INT NOT NULL DEFAULT 0,
    `npcs_killed` INT NOT NULL DEFAULT 0,
    `plants_picked` INT NOT NULL DEFAULT 0,
    `drugs_used` INT NOT NULL DEFAULT 0,
    `drugs_sold` INT NOT NULL DEFAULT 0,
    `title_tier` INT NOT NULL DEFAULT 1,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gangs_war_history` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `zone_key` VARCHAR(64) NOT NULL,
    `attacker` VARCHAR(64) NOT NULL,
    `defender` VARCHAR(64) DEFAULT NULL,
    `winner` VARCHAR(64) NOT NULL,
    `attacker_score` INT NOT NULL DEFAULT 0,
    `defender_score` INT NOT NULL DEFAULT 0,
    `ended_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_citizens` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(80) NOT NULL,
    `full_name` VARCHAR(120) NOT NULL,
    `date_of_birth` VARCHAR(20) DEFAULT NULL,
    `phone_number` VARCHAR(30) DEFAULT NULL,
    `address` VARCHAR(180) DEFAULT NULL,
    `licenses_status` VARCHAR(20) NOT NULL DEFAULT 'valid',
    `notes` TEXT,
    `flags` LONGTEXT DEFAULT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `ux_mdt_citizens_identifier` (`identifier`),
    KEY `ix_mdt_citizens_name` (`full_name`),
    KEY `ix_mdt_citizens_phone` (`phone_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_reports` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `report_type` VARCHAR(20) NOT NULL,
    `title` VARCHAR(120) NOT NULL,
    `summary` VARCHAR(1000) DEFAULT NULL,
    `narrative` LONGTEXT,
    `involved_citizens` LONGTEXT,
    `involved_vehicles` LONGTEXT,
    `charges` LONGTEXT,
    `total_fines` INT NOT NULL DEFAULT 0,
    `total_jail_time` INT NOT NULL DEFAULT 0,
    `evidence_refs` LONGTEXT,
    `officer_identifier` VARCHAR(80) NOT NULL,
    `officer_name` VARCHAR(120) NOT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    KEY `ix_mdt_reports_officer` (`officer_identifier`),
    KEY `ix_mdt_reports_type` (`report_type`),
    KEY `ix_mdt_reports_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_warrants` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `citizen_identifier` VARCHAR(80) NOT NULL,
    `title` VARCHAR(120) NOT NULL,
    `reason` TEXT,
    `report_id` INT UNSIGNED DEFAULT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'active',
    `issued_by_identifier` VARCHAR(80) NOT NULL,
    `issued_by_name` VARCHAR(120) NOT NULL,
    `issued_at` DATETIME NOT NULL,
    `expires_at` DATETIME DEFAULT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    KEY `ix_mdt_warrants_citizen` (`citizen_identifier`),
    KEY `ix_mdt_warrants_status` (`status`),
    KEY `ix_mdt_warrants_report` (`report_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_bolos` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `bolo_type` VARCHAR(20) NOT NULL,
    `title` VARCHAR(120) NOT NULL,
    `description` TEXT,
    `target_identifier` VARCHAR(80) DEFAULT NULL,
    `target_plate` VARCHAR(12) DEFAULT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'active',
    `created_by_identifier` VARCHAR(80) NOT NULL,
    `created_by_name` VARCHAR(120) NOT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    KEY `ix_mdt_bolos_status` (`status`),
    KEY `ix_mdt_bolos_type` (`bolo_type`),
    KEY `ix_mdt_bolos_target_plate` (`target_plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_evidence` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `report_id` INT UNSIGNED NOT NULL,
    `evidence_type` VARCHAR(40) NOT NULL,
    `description` TEXT,
    `image_url` VARCHAR(350) DEFAULT NULL,
    `metadata` LONGTEXT,
    `added_by_identifier` VARCHAR(80) NOT NULL,
    `added_by_name` VARCHAR(120) NOT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    KEY `ix_mdt_evidence_report` (`report_id`),
    KEY `ix_mdt_evidence_type` (`evidence_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_radar_logs` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `plate` VARCHAR(12) NOT NULL,
    `speed` INT NOT NULL DEFAULT 0,
    `location` VARCHAR(120) DEFAULT NULL,
    `radar_source` VARCHAR(40) NOT NULL,
    `officer_identifier` VARCHAR(80) NOT NULL,
    `officer_name` VARCHAR(120) NOT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    KEY `ix_mdt_radar_plate` (`plate`),
    KEY `ix_mdt_radar_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_charges` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `code` VARCHAR(20) NOT NULL,
    `label` VARCHAR(120) NOT NULL,
    `category` VARCHAR(80) NOT NULL,
    `fine` INT NOT NULL DEFAULT 0,
    `jail_time` INT NOT NULL DEFAULT 0,
    `active` TINYINT(1) NOT NULL DEFAULT 1,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `ux_mdt_charges_code` (`code`),
    KEY `ix_mdt_charges_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_officers` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(80) NOT NULL,
    `full_name` VARCHAR(120) NOT NULL,
    `callsign` VARCHAR(40) DEFAULT NULL,
    `rank_label` VARCHAR(40) DEFAULT NULL,
    `notes` TEXT,
    `activity_log` LONGTEXT,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `ux_mdt_officers_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_vehicles` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `plate` VARCHAR(12) NOT NULL,
    `owner_identifier` VARCHAR(80) DEFAULT NULL,
    `model_name` VARCHAR(80) DEFAULT NULL,
    `vehicle_class` VARCHAR(40) DEFAULT NULL,
    `color` VARCHAR(30) DEFAULT NULL,
    `stolen` TINYINT(1) NOT NULL DEFAULT 0,
    `flags` LONGTEXT,
    `notes` TEXT,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `ux_mdt_vehicles_plate` (`plate`),
    KEY `ix_mdt_vehicles_owner` (`owner_identifier`),
    KEY `ix_mdt_vehicles_stolen` (`stolen`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
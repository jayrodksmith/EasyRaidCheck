# Changelog for EasyRaidCheck

## [Unreleased]

### Added

- HP rebuild percentage status in table
- LSI rebuild percentage status in table
- HP Array status to table
- PERC Array Status to table
- Added drives not part of array into output
- Rework of LSI/PERC to support multiple controllers

### Fixed

- CrystalDiskInfo url updated to allow downloads
- PERC script now matches LSI script

## [1.4.0] - 25-04-2024

### Added

- Added storing results to json
- Added more supported raid controllers based on LSI
- Exit code 888 to allow ninja to see script failures
- 2 Extra WYSIWYG custom fields for Virtual drives and Controller details

### Changed

- Updated HP cli and ADU to latest version ( supports more controllers )
- Folder structure now based on programdata folder
- Main function controls location of CLI's

## [1.3.0] - 22-04-2024

### Added

- Added to store drives found by smart by default, if no raid controllers found

## [1.2.0] - 22-04-2024

### Added

- Added detection of PERC (Dell) based controllers, perccli is stored on this repository

## [1.1.0] - 17-04-2024

### Added

- Added detection of Smart values using CrystalDiskInfo and mark drive as danger if not "Good"

## [1.0.1] - 17-04-2024

### Fixed

- Fixed bug with writing incorrect Healthy status to ninja text field

## [1.0.0] - 17-04-2024

### Added

- First Release
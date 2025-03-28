## [0.4.1] - 2025-03-28

* Manual release


## [0.4.0] - 2025-03-28

### Added
- Restructured CLI commands for better organization
- Added dedicated NotebookCommand class for notebook-related commands
- Improved command structure consistency

### Fixed
- Fixed `notebook` command not being recognized issue
- Ensured proper subcommand registration

## [0.3.4] - 2025-03-28

* Manual release


## [0.3.3] - 2025-03-28

* Manual release


# Changelog

## [0.3.2] - 2024-03-28

### Added
- Improved exposure of --version flag for CLI command

## [0.3.1] - 2024-03-27

### Fixed
- Fixed issue with executable not being properly included in the gem package
- Ensured all necessary files are included in the gem
- Updated documentation with clearer installation instructions

## [0.3.0] - 2024-03-27

### Added
- Task export and import functionality with JSON and CSV formats
- Task templates system with reusable patterns
- Dynamic due date calculations for templates
- Database schema versioning for easier updates
- Improved CLI experience with better feedback
- Extended test coverage for new features
- GitHub Actions CI/CD workflow for automated testing and releases

### Changed
- Enhanced documentation with examples
- Extended database schema to support templates
- Improved exports directory organization
- Better error handling for task operations

## [0.2.0] - 2024-03-27

### Added
- Advanced task features (descriptions, due dates, priorities, tags)
- Task filtering and search capabilities
- Task statistics and analytics
- Colored output for better readability
- Improved CLI interface with command aliases
- Enhanced error messages

### Changed
- Reorganized code structure for better maintainability
- Improved database schema for additional task attributes
- Enhanced documentation with more examples

## [0.1.0] - 2024-03-27

### Added
- Initial release
- Basic notebook management (create, list, delete)
- Task CRUD operations
- Task categorization (todo, in progress, done, archived)
- SQLite database integration
- Basic CLI interface

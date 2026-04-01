# Deployment Scripts Directory

This directory contains deployment-related scripts and configurations for the AI Setup system.

## Contents

### Modules (`modules/`)
Contains the modular components of the deployment system:
- `00-header.sh` - Core configuration and utilities
- `01-ai-docs.sh` - AI documentation deployment
- `02-docs.sh` - Documentation templates
- `03-claude-config.sh` - Claude Code configuration
- `04-validation.sh` - Validation system
- `05-git-scripts.sh` - Git author management
- `06-hooks.sh` - Validation hooks
- `07-finalize.sh` - Cleanup and final steps

### Build Process
The modular system allows for:
- Easier maintenance of the deployment script
- Independent testing of modules
- Selective deployment of components
- Better organization and readability

### Usage
These modules are automatically assembled into the main deployment script during the build process. They should not be executed individually in most cases.

## Development

When modifying the deployment system:
1. Edit the appropriate module in `modules/`
2. Test the module independently if possible
3. Rebuild the main deployment script
4. Test the complete deployment

## Version Control
All modules should be kept in sync with the main deployment script version to ensure compatibility.

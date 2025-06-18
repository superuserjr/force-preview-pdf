# Force Preview PDF Default - MDM Deployment Script

A robust macOS script for MDM deployment that forcefully sets Apple Preview as the default PDF handler, overriding Adobe Acrobat or Adobe Reader settings.

## Overview

This script addresses the common enterprise issue where Adobe Acrobat/Reader aggressively takes over as the default PDF handler, even after users or IT attempt to change it. The script uses multiple approaches to ensure Preview becomes and remains the default PDF application.

## Features

- **Aggressive Adobe Process Management**: Kills all Adobe processes and prevents them from re-registering
- **Launch Agent Control**: Disables Adobe launch agents that would restart services
- **LaunchServices Reset**: Completely rebuilds the file association database
- **Multi-User Support**: Applies changes for all user accounts on the system
- **MDM-Ready**: Designed to run as root via MDM platforms (Mosyle, Jamf, Kandji, etc.)
- **Detailed Logging**: Timestamped logs with clear status indicators
- **Graceful Error Handling**: Won't fail if Adobe isn't installed

## Configuration Profile (mobileconfig)

The included `force_preview_pdf_default_mdm.mobileconfig` file provides an alternative or complementary approach to setting Preview as the default PDF handler through macOS configuration profiles.

### What is the mobileconfig?

The mobileconfig is an Apple Configuration Profile that uses the LaunchServices (LSHandlers) payload to define system-wide file associations. Unlike the script which makes changes after the fact, the configuration profile establishes these preferences at the system level and prevents users from changing them.

### Key Components

1. **LaunchServices Handlers**: The profile defines multiple handlers to catch all PDF file types:
   - `com.adobe.pdf` - Adobe's PDF content type
   - `public.pdf` - Apple's standard PDF UTI
   - `com.adobe.acrobat.pdf` - Acrobat-specific PDF type
   - `net.adobe.pdf` - Legacy Adobe PDF type
   - `pdf` file extension - Catches files by extension

2. **Profile Metadata**:
   - PayloadIdentifier: `com.organization.pdf-preview-default-profile`
   - PayloadScope: `System` - Applies to all users
   - PayloadType: `com.apple.LSHandlers` - LaunchServices configuration

### When to Use the mobileconfig vs Script

**Use the mobileconfig when:**
- You want a preventative approach that blocks Adobe from taking over
- You need a persistent setting that users cannot change
- You're deploying to new machines or doing initial setup
- You want a cleaner, system-level solution

**Use the script when:**
- Adobe has already taken over as the default
- You need to clean up existing Adobe processes and agents
- You want to reset corrupted LaunchServices databases
- You need immediate results on already-configured machines

**Best Practice**: Deploy both! Use the mobileconfig for ongoing enforcement and the script for initial cleanup.

### Deploying the mobileconfig

#### Via Mosyle
1. Navigate to Management > Profiles
2. Click "Add Profile" and select "Custom Profile"
3. Upload the `force_preview_pdf_default_mdm.mobileconfig` file
4. Name it appropriately (e.g., "Force Preview PDF Default")
5. Assign to target devices or groups

#### Via Jamf
1. Go to Computers > Configuration Profiles
2. Click "New" and select "Upload"
3. Upload the mobileconfig file
4. Configure scope and deployment settings

#### Via Kandji
1. Navigate to Library > Custom Profiles
2. Add new Custom Profile
3. Upload the mobileconfig file
4. Configure assignment rules

### Customizing the mobileconfig

To customize for your organization:
1. Replace `Your Organization` with your company name
2. Update the PayloadIdentifier to use your reverse domain (e.g., `com.yourcompany.pdf-preview-default`)
3. Generate new UUIDs for PayloadUUID values if creating multiple versions

### Technical Details

The profile works by registering Preview.app (`com.apple.Preview`) as the handler for all PDF-related content types and extensions. The `LSHandlerRoleAll` key ensures Preview handles all operations (viewing, editing, printing) for PDFs. The multiple handler entries ensure comprehensive coverage of all PDF type identifiers that Adobe products might use.

## How It Works

```mermaid
graph TD
    A[Force Preview PDF Default MDM Script] --> B[Kill Adobe Processes]
    A --> C[Disable Launch Agents]
    A --> D[Clear LaunchServices]
    A --> E[Set Preview as Default]
    
    B --> B1[Adobe Acrobat]
    B --> B2[Creative Cloud]
    B --> B3[Background Services]
    
    C --> C1[System Launch Agents]
    C --> C2[User Launch Agents]
    
    D --> D1[Remove Adobe from Registry]
    D --> D2[Clear Preferences]
    D --> D3[Rebuild Database]
    
    E --> E1[Register Preview.app]
    E --> E2[Create User Preferences]
    E --> E3[Restart Services]
```

## Script Actions

1. **Kill Adobe Processes**: Stops all running Adobe applications and services
2. **Disable Launch Agents**: Prevents Adobe services from restarting at login
3. **Unregister Adobe Apps**: Removes Adobe applications from LaunchServices
4. **Clear Preferences**: Removes all existing PDF file associations
5. **Restart Services**: Restarts preference daemons
6. **Rebuild Database**: Reconstructs the LaunchServices database
7. **Register Preview**: Explicitly registers Preview.app
8. **Set User Preferences**: Creates preference files for each user
9. **Optional: Clear File Attributes** (disabled by default for performance)
10. **Restart UI Services**: Restarts Finder and Dock for immediate effect

## Requirements

- macOS 10.14 or later
- Root/admin privileges (automatic when deployed via MDM)
- Apple Preview.app installed (standard on all macOS systems)

## Deployment

### Via Mosyle

1. Navigate to Management > Custom Commands
2. Create new Custom Command
3. Upload `force_preview_pdf_default_mdm.sh`
4. Set to run as root
5. Deploy to target devices

### Via Jamf

1. Go to Settings > Computer Management > Scripts
2. Upload the script
3. Create a policy to run the script
4. Scope to target computers

### Manual Execution

```bash
sudo ./force_preview_pdf_default_mdm.sh
```

## Performance Considerations

The script typically completes in 45-60 seconds. The longest operation is rebuilding the LaunchServices database (~30 seconds).

### Optional Step 9

Step 9 (clearing file-specific PDF associations) is commented out by default because:
- It's the slowest operation (can add several minutes)
- Scans all PDFs in Desktop, Documents, and Downloads
- Only needed if users have manually set individual PDFs to "Always Open With" Adobe
- The system-wide changes are usually sufficient

To enable if needed, uncomment the code in Step 9.

## Logging

The script provides detailed logging with timestamps and status indicators:
- ✓ Success
- ⚠ Warning (non-critical issue)
- ℹ Information (no action needed)

Example output:
```
[13:54:28] Step 1: Stopping Adobe processes...
[13:54:28]   ✓ Killed: Adobe Acrobat
[13:54:28]   ✓ Killed: AdobeResourceSynchronizer
```

## Troubleshooting

### PDFs Still Open in Adobe

1. Ensure the script ran successfully (check logs)
2. Have the user log out and back in
3. If issue persists, enable Step 9 to clear file-specific associations
4. Check if Adobe has been reinstalled

### Script Fails

- Verify running with root privileges
- Check if paths to applications are correct
- Ensure macOS version compatibility

### Adobe Keeps Coming Back

- Check for MDM policies that might be reinstalling Adobe
- Look for third-party software that depends on Adobe
- Consider scheduling the script to run periodically

## Why This Script Is Necessary

Adobe products use several mechanisms to maintain default handler status:
- Background processes that re-register periodically
- Launch agents that start at login
- Aggressive LaunchServices registration
- File-specific associations that override system defaults

This script addresses all these mechanisms comprehensively.

## Testing

1. Run the script
2. Double-click a PDF file
3. Verify it opens in Preview
4. Reboot and test again
5. Check after a few days to ensure persistence

## License

This script is provided as-is for enterprise use. Feel free to modify for your organization's needs.

## Support

For issues or questions:
- Check the detailed logs first
- Ensure Adobe isn't being reinstalled by other policies
- Test with Step 9 enabled if needed

---

**Keywords**: macOS, PDF, Preview, Adobe, Acrobat, MDM, Mosyle, Jamf, LaunchServices, enterprise, deployment 
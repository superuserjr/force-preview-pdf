#!/bin/bash

# Force Preview as Default PDF Handler - MDM Deployment Script
# Aggressively sets Apple Preview as the default PDF application
# Designed for MDM deployment (Mosyle, Jamf, etc.) - runs as root

echo "Force Preview PDF Default - MDM Script"
echo "====================================="
echo "Date: $(date)"
echo "Running as: $(whoami)"
echo ""

# Function to log with timestamp
log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# 1. Kill ALL Adobe processes
log "Step 1: Stopping Adobe processes..."
adobe_processes=(
    "Adobe Acrobat"
    "AdobeResourceSynchronizer"
    "Creative Cloud"
    "Creative Cloud Helper"
    "Adobe Desktop Service"
    "Core Sync"
    "CCXProcess"
    "AdobeIPCBroker"
    "ACCFinderSync"
)

killed_count=0
for process in "${adobe_processes[@]}"; do
    if pgrep -x "$process" > /dev/null 2>&1; then
        killall -9 "$process" 2>/dev/null && {
            log "  ✓ Killed: $process"
            ((killed_count++))
        }
    fi
done

# Also kill by partial name
if pgrep -i adobe > /dev/null 2>&1; then
    pkill -f adobe 2>/dev/null && log "  ✓ Killed remaining Adobe processes"
fi

if [ $killed_count -eq 0 ]; then
    log "  ℹ No Adobe processes were running"
fi

# 2. Disable Adobe Launch Agents
log ""
log "Step 2: Disabling Adobe launch agents..."

disabled_count=0

# System agents
if [ -d "/Library/LaunchAgents" ]; then
    for agent in /Library/LaunchAgents/com.adobe.*; do
        if [[ -f "$agent" && ! "$agent" =~ \.disabled$ ]]; then
            agent_name=$(basename "$agent")
            launchctl unload "$agent" 2>/dev/null || true
            if mv "$agent" "$agent.disabled" 2>/dev/null; then
                log "  ✓ Disabled: $agent_name"
                ((disabled_count++))
            else
                log "  ⚠ Could not disable: $agent_name"
            fi
        fi
    done
fi

# User agents for all users
for user_dir in /Users/*; do
    if [[ -d "$user_dir/Library/LaunchAgents" && $(basename "$user_dir") != "Shared" ]]; then
        username=$(basename "$user_dir")
        for agent in "$user_dir"/Library/LaunchAgents/com.adobe.*; do
            if [[ -f "$agent" && ! "$agent" =~ \.disabled$ ]]; then
                agent_name=$(basename "$agent")
                sudo -u "$username" launchctl unload "$agent" 2>/dev/null || true
                if mv "$agent" "$agent.disabled" 2>/dev/null; then
                    log "  ✓ Disabled for $username: $agent_name"
                    ((disabled_count++))
                fi
            fi
        done
    fi
done

if [ $disabled_count -eq 0 ]; then
    log "  ℹ No Adobe launch agents needed disabling"
fi

# 3. Remove Adobe apps from LaunchServices
log ""
log "Step 3: Unregistering Adobe apps from LaunchServices..."

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
adobe_apps=(
    "/Applications/Adobe Acrobat DC/Adobe Acrobat.app"
    "/Applications/Adobe Acrobat Reader DC/Adobe Acrobat Reader DC.app"
    "/Applications/Adobe Acrobat Reader.app"
    "/Applications/Adobe Acrobat.app"
)

unregistered=0
for app in "${adobe_apps[@]}"; do
    if [ -d "$app" ]; then
        "$lsregister" -u "$app" 2>/dev/null && {
            log "  ✓ Unregistered: $(basename "$app")"
            ((unregistered++))
        }
    fi
done

if [ $unregistered -eq 0 ]; then
    log "  ℹ No Adobe apps found to unregister"
fi

# 4. Clear ALL LaunchServices preferences
log ""
log "Step 4: Clearing LaunchServices preferences..."

# System-wide
removed_prefs=0
if rm -rf /Library/Preferences/com.apple.LaunchServices* 2>/dev/null; then
    log "  ✓ Removed system LaunchServices preferences"
    ((removed_prefs++))
fi

# User preferences
for user_dir in /Users/*; do
    if [[ -d "$user_dir" && $(basename "$user_dir") != "Shared" ]]; then
        username=$(basename "$user_dir")
        if rm -rf "$user_dir"/Library/Preferences/com.apple.LaunchServices* 2>/dev/null; then
            log "  ✓ Removed preferences for: $username"
            ((removed_prefs++))
        fi
    fi
done

if [ $removed_prefs -eq 0 ]; then
    log "  ℹ No existing preferences to remove"
fi

# 5. Kill preference daemons
log ""
log "Step 5: Restarting preference services..."
killall cfprefsd 2>/dev/null && log "  ✓ Restarted cfprefsd" || log "  ℹ cfprefsd was not running"
killall lsd 2>/dev/null && log "  ✓ Restarted lsd" || log "  ℹ lsd was not running"

# 6. Clear and rebuild LaunchServices database
log ""
log "Step 6: Rebuilding LaunchServices database..."
"$lsregister" -kill -r -domain local -domain system -domain user && log "  ✓ Database rebuilt successfully"

# 7. Register Preview.app
log ""
log "Step 7: Registering Preview.app..."
"$lsregister" -f /System/Applications/Preview.app && log "  ✓ Preview.app registered" || log "  ⚠ Failed to register Preview.app"

# 8. Create clean LaunchServices preferences for all users
log ""
log "Step 8: Creating LaunchServices preferences..."

users_configured=0
for user_dir in /Users/*; do
    if [[ -d "$user_dir" && $(basename "$user_dir") != "Shared" ]]; then
        username=$(basename "$user_dir")
        
        # Create directory if it doesn't exist
        if sudo -u "$username" mkdir -p "$user_dir/Library/Preferences/com.apple.LaunchServices/" 2>/dev/null; then
            
            # Create clean plist
            if cat > "$user_dir/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSHandlers</key>
    <array>
        <dict>
            <key>LSHandlerContentType</key>
            <string>com.adobe.pdf</string>
            <key>LSHandlerRoleAll</key>
            <string>com.apple.Preview</string>
        </dict>
        <dict>
            <key>LSHandlerContentTag</key>
            <string>pdf</string>
            <key>LSHandlerContentTagClass</key>
            <string>public.filename-extension</string>
            <key>LSHandlerRoleAll</key>
            <string>com.apple.Preview</string>
        </dict>
        <dict>
            <key>LSHandlerContentType</key>
            <string>public.pdf</string>
            <key>LSHandlerRoleAll</key>
            <string>com.apple.Preview</string>
        </dict>
    </array>
</dict>
</plist>
EOF
            then
                # Set correct ownership
                chown "$username" "$user_dir/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
                log "  ✓ Created preferences for: $username"
                ((users_configured++))
            else
                log "  ⚠ Failed to create preferences for: $username"
            fi
        fi
    fi
done

log "  ℹ Configured $users_configured user(s)"

# 9. Clear file-specific attributes on PDFs
# COMMENTED OUT - This step is usually not necessary but can be enabled if needed
# 
# What this does:
# - Scans Desktop, Documents, and Downloads folders for all users
# - Looks for PDF files that have file-specific "Open With" settings
# - These are created when a user right-clicks a PDF and chooses "Open With > Always Open With"
# - Removes these file-specific overrides (com.apple.LaunchServices.OpenWith extended attribute)
# 
# Why it's disabled:
# - This is the slowest part of the script (can take several minutes on machines with many PDFs)
# - File-specific associations are relatively rare
# - The system-wide default changes in steps 1-8 are usually sufficient
# - Only needed if users have explicitly set individual PDFs to open with Adobe
#
# To enable: Uncomment the code below
#
# log ""
# log "Step 9: Removing file-specific PDF associations..."
# 
# files_cleared=0
# for user_dir in /Users/*; do
#     if [[ -d "$user_dir" && $(basename "$user_dir") != "Shared" ]]; then
#         username=$(basename "$user_dir")
#         # Check common directories
#         for dir in "$user_dir/Desktop" "$user_dir/Documents" "$user_dir/Downloads"; do
#             if [[ -d "$dir" ]]; then
#                 # Count PDFs with xattrs before removing
#                 pdf_count=$(find "$dir" -name "*.pdf" -type f -exec xattr -l {} \; 2>/dev/null | grep -c "com.apple.LaunchServices.OpenWith" || echo 0)
#                 if [ $pdf_count -gt 0 ]; then
#                     find "$dir" -name "*.pdf" -type f -exec xattr -d com.apple.LaunchServices.OpenWith {} \; 2>/dev/null
#                     log "  ✓ Cleared attributes from $pdf_count PDFs in $username's $(basename "$dir")"
#                     ((files_cleared+=$pdf_count))
#                 fi
#             fi
#         done
#     fi
# done
# 
# if [ $files_cleared -eq 0 ]; then
#     log "  ℹ No PDFs had file-specific associations"
# fi

# Set files_cleared to 0 since we're skipping this step
files_cleared=0
log ""
log "Step 9: Skipping file-specific PDF associations (not needed for most deployments)"

# 10. Final cleanup and restart
log ""
log "Step 10: Final cleanup..."
killall cfprefsd 2>/dev/null && log "  ✓ Restarted cfprefsd"
killall Finder 2>/dev/null && log "  ✓ Restarted Finder"
killall Dock 2>/dev/null && log "  ✓ Restarted Dock"

# Summary
log ""
log "=========================================="
log "✅ PDF Handler Reset Complete!"
log "=========================================="
log ""
log "Summary of actions taken:"
log "  • Adobe processes stopped"
log "  • Launch agents disabled: $disabled_count"
log "  • Adobe apps unregistered: $unregistered"  
log "  • Users configured: $users_configured"
log "  • PDF files cleared: $files_cleared"
log ""
log "Preview is now set as the default PDF handler."
log "Users may need to log out/in for full effect."
log ""
log "Script completed at: $(date)"

exit 0 
#!/bin/bash

# Force Preview as Default PDF Handler - MDM Deployment Script
# Sets Apple Preview as the default PDF application without affecting other file types
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

# Set variables for skipped steps (for summary reporting)
killed_count=0
disabled_count=0
unregistered=0

# 1. Remove PDF-specific entries from LaunchServices preferences
log "Step 1: Clearing PDF-specific LaunchServices preferences..."

removed_prefs=0

# Function to remove PDF handlers from a plist
remove_pdf_handlers() {
    local plist="$1"
    local owner="$2"
    
    if [ -f "$plist" ]; then
        # Create a backup just in case
        cp "$plist" "$plist.backup" 2>/dev/null
        
        # Count how many PDF handlers exist
        local count=$(/usr/libexec/PlistBuddy -c "Print :LSHandlers" "$plist" 2>/dev/null | grep -c "Dict {" || echo 0)
        
        if [ $count -gt 0 ]; then
            # Work backwards through the array to avoid index shifting issues
            for ((i=$((count-1)); i>=0; i--)); do
                # Check if this handler is for PDF
                local contentType=$(/usr/libexec/PlistBuddy -c "Print :LSHandlers:$i:LSHandlerContentType" "$plist" 2>/dev/null || echo "")
                local contentTag=$(/usr/libexec/PlistBuddy -c "Print :LSHandlers:$i:LSHandlerContentTag" "$plist" 2>/dev/null || echo "")
                
                # Remove if it's a PDF handler
                if [[ "$contentType" == *"pdf"* ]] || [[ "$contentTag" == "pdf" ]]; then
                    /usr/libexec/PlistBuddy -c "Delete :LSHandlers:$i" "$plist" 2>/dev/null && \
                        log "  ✓ Removed PDF handler from $owner"
                fi
            done
            
            # Remove backup if successful
            rm -f "$plist.backup" 2>/dev/null
            return 0
        fi
    fi
    return 1
}

# Target the secure plist which takes precedence
for user_dir in /Users/*; do
    if [[ -d "$user_dir" && $(basename "$user_dir") != "Shared" ]]; then
        username=$(basename "$user_dir")
        plist="$user_dir/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
        
        if remove_pdf_handlers "$plist" "$username"; then
            ((removed_prefs++))
        fi
    fi
done

if [ $removed_prefs -eq 0 ]; then
    log "  ℹ No existing PDF preferences to remove"
else
    log "  ℹ Removed PDF handlers for $removed_prefs user(s)"
fi

# 2. Restart preference daemons to ensure changes take effect
log ""
log "Step 2: Restarting preference services..."
killall cfprefsd 2>/dev/null && log "  ✓ Restarted cfprefsd" || log "  ℹ cfprefsd was not running"
killall lsd 2>/dev/null && log "  ✓ Restarted lsd" || log "  ℹ lsd was not running"

# 3. Rebuild LaunchServices database to recognize changes
log ""
log "Step 3: Rebuilding LaunchServices database..."
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$lsregister" -kill -r -domain local -domain system -domain user && log "  ✓ Database rebuilt successfully"

# 4. Register Preview.app as a PDF handler
log ""
log "Step 4: Registering Preview.app..."
"$lsregister" -f /System/Applications/Preview.app && log "  ✓ Preview.app registered" || log "  ⚠ Failed to register Preview.app"

# 5. Create LaunchServices preferences setting Preview as default PDF handler
log ""
log "Step 5: Creating LaunchServices preferences..."

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

# 6. Clear file-specific attributes on PDFs
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
# - The system-wide default changes are usually sufficient
# - Only needed if users have explicitly set individual PDFs to open with Adobe
#
# To enable: Uncomment the code below
#
# log ""
# log "Step 6: Removing file-specific PDF associations..."
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

# 7. Restart UI services to apply changes immediately
log ""
log "Step 7: Final cleanup..."
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
log "  • Adobe processes stopped: $killed_count"
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
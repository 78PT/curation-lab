#!/bin/sh

# Fail the script if any command fails
set -e

echo "Starting ci_post_clone.sh..."

# The script runs inside the ci_scripts directory, so we go up to the project root
cd ..

PLIST_PATH="CurationLab/Keys.plist"

echo "Creating Keys.plist at $PLIST_PATH..."

# Write plist contents, substituting environment variables
cat <<EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>GeminiAPIKey</key>
	<string>${GEMINI_API_KEY}</string>
	<key>GroqAPIKey</key>
	<string>${GROQ_API_KEY}</string>
</dict>
</plist>
EOF

echo "Keys.plist successfully generated from environment variables!"

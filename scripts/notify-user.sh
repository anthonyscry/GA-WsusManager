#!/bin/bash
# User notification script - makes noise and visual alert

MESSAGE="${1:-Attention needed at keyboard!}"

# Print banner
echo ""
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!!! ATTENTION: $MESSAGE"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo ""

# Terminal bell (multiple times)
for i in {1..5}; do
    printf '\a'
    sleep 0.3
done

# Try notify-send if available
notify-send "Claude Code" "$MESSAGE" --urgency=critical 2>/dev/null || true

# Try espeak if available
espeak "$MESSAGE" 2>/dev/null || true

# Try paplay if available (system notification sound)
paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null || true

echo ">>> $MESSAGE <<<"

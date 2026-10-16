echo "Tell ASUS ROG ALC285 users how to lift the 80% Master cap"

# Install used to set the ALC285 hardware Master to 80% under the soft mixer,
# which never moves it again, so the volume slider's 100% sat 12.75 dB below
# full scale on a 0-87 codec. New installs now use 100%. Raising it here would
# make the speakers jump in volume during an update, so this leaves Master alone
# and only says how to raise it. omarchy-migrate shows the echo once in the
# update terminal; the notification outlives that scrollback.
# Without the soft mixer PipeWire drives Master and 80% is just the volume.

omarchy-hw-asus-rog || exit 0
[[ -f ~/.config/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf ]] || exit 0

card=$(aplay -l 2>/dev/null | grep -i "ALC285" | head -1 | sed 's/^card [0-9]*: \([^ ]*\) .*/\1/' || true)
[[ -n $card ]] || exit 0

[[ $(amixer -c "$card" sget Master 2>/dev/null) == *"[80%]"* ]] || exit 0

command="amixer -c $card set Master 100% unmute"
echo "  The speaker hardware volume is capped at 80%, so 100% on the volume slider is 12.75 dB below full volume."
echo "  To lift the cap (speakers get louder at the same slider setting), run: $command"
omarchy-notification-send "Speaker volume is capped at 80%" "100% on the slider is 12.75 dB below full volume. To lift the cap (louder at the same setting), run: $command" || true

#!/usr/bin/env bash
set -euo pipefail

# File and PAR2 base names
FILENAME="dummy.bin"
ORIGINAL="${FILENAME}.original"
PAR2BASE="dummy_par2"

echo "[1] Clean up old demo files (if any)"
rm -f "$FILENAME" "$ORIGINAL" "${PAR2BASE}.par2" "${PAR2BASE}".vol*.par2

echo "[2] Create dummy file (64 KiB random data)"
dd if=/dev/urandom of="$FILENAME" bs=1K count=64 status=none

echo "[3] Save a copy of the original for later comparison"
cp "$FILENAME" "$ORIGINAL"

echo "[4] Create 10% redundancy with par2"
# -r10 : around 10% redundancy
par2 create -r10 "$PAR2BASE" "$FILENAME"

echo
echo "== par2 verify: before corruption =="
par2 verify "${PAR2BASE}.par2"

echo
echo "[5] Flip a single bit in the file to simulate a tiny corruption"
python3 - << 'EOF'
filename = "dummy.bin"
idx = 123  # byte index to corrupt

with open(filename, "rb") as f:
    data = bytearray(f.read())

print(f"Original byte at index {idx}: 0x{data[idx]:02x}")
data[idx] ^= 0x01  # flip the lowest bit
print(f"Corrupted byte at index {idx}: 0x{data[idx]:02x}")

with open(filename, "wb") as f:
    f.write(data)
EOF

echo
echo "== par2 verify: after single-bit corruption =="
set +e
par2 verify "${PAR2BASE}.par2"
VERIFY_STATUS=$?
set -e

if [ "$VERIFY_STATUS" -eq 0 ]; then
    echo "[Warning] par2 verify did not report any damage (unexpected for this demo)."
else
    echo "[Expected] par2 reported damage for the single-bit corruption."
fi

echo
echo "[6] Repair the single-bit corruption with par2"
par2 repair "${PAR2BASE}.par2"

echo
echo "== par2 verify: after repair (single-bit) =="
par2 verify "${PAR2BASE}.par2"

echo
echo "[7] Compare repaired file with original copy"
if cmp -s "$FILENAME" "$ORIGINAL"; then
    echo "[OK] Repaired file is byte-identical to the original."
else
    echo "[ERROR] Repaired file differs from the original!"
fi

###############################################################################
# EXTRA DEMO: corruption beyond 10% redundancy (detectable but NOT fixable)
###############################################################################

echo
echo "[8] Create heavy corruption that exceeds the 10% redundancy"
echo "    (Overwriting about half of the file with zeros)"

# For this demo we know the file is 64 KiB, so corrupt half of it (32 KiB).
# This will destroy far more than 10% of the data blocks, so repair should fail.
BYTES_TO_CORRUPT=$(( (64 * 1024) / 2 ))  # 32 KiB

dd if=/dev/zero of="$FILENAME" bs=1 count="$BYTES_TO_CORRUPT" conv=notrunc status=none

echo
echo "== par2 verify: after heavy corruption =="
set +e
par2 verify "${PAR2BASE}.par2"
VERIFY_STATUS2=$?
set -e

if [ "$VERIFY_STATUS2" -eq 0 ]; then
    echo "[Warning] par2 verify did not report damage (unexpected for heavy corruption)."
else
    echo "[Expected] par2 reported heavy damage."
fi

echo
echo "[9] Try to repair heavily corrupted file (this should NOT be possible)"
set +e
par2 repair "${PAR2BASE}.par2"
REPAIR_STATUS2=$?
set -e

if [ "$REPAIR_STATUS2" -eq 0 ]; then
    echo "[Warning] par2 repair succeeded unexpectedly."
    echo "          (Maybe the redundancy was increased or corruption was smaller than expected.)"
else
    echo "[Expected] par2 repair reported that repair is not possible due to too much damage."
fi

echo
echo "Done. Demo files in the current directory:"
ls -1 "$FILENAME" "$ORIGINAL" "${PAR2BASE}.par2" "${PAR2BASE}".vol*.par2 2>/dev/null || true


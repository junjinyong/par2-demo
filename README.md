# par2-demo

This repository contains a small, self-contained shell script that demonstrates how
`par2` (parity archives) can:

1. Detect and repair small errors (e.g. a single flipped bit).
2. Detect but *not* repair damage that exceeds the configured redundancy.

It is intended as an educational example for people who are new to par2 and
forward error correction on files.

> Note  
> The script and this README were written by GitHub user `junjinyong`
> with the help of an LLM (ChatGPT). Feel free to reuse or modify them.

---

## What is par2?

`par2` (Parity Archive Volume Set, version 2):

- Splits your data into data blocks.
- Computes additional parity (recovery) blocks using Reed–Solomon codes.
- As long as you have enough total blocks (data + parity), it can
  reconstruct damaged or missing data blocks.
- Is popular for error-tolerant file storage and transfer (e.g. Usenet,
  long-term archives, flaky disks).

Roughly speaking:

> If you create 10% redundancy, par2 can repair up to about 10% worth of
> data blocks lost or corrupted.  
> If more than that is damaged, it can still detect the error, but cannot fully
> reconstruct the original file.

This demo script shows both sides: “fixable” and “too much damage”.

---

## Requirements

You need:

- A POSIX shell environment (Linux, WSL, etc.).
- `par2` (par2cmdline).
- `python3`.
- Standard Unix tools: `dd`, `cmp`, `rm`, `ls`, etc.

On Ubuntu / Debian, you can install dependencies with:

    sudo apt update
    sudo apt install par2 python3

---

## Files

- `par2_single_bit_demo.sh`  
  Main demo script.  
  It runs two scenarios in the current directory:

  1. Single-bit corruption → par2 detects and successfully repairs.
  2. Heavy corruption (>10% of file) → par2 detects but cannot repair.

No other files are required; the script creates and cleans up its own demo data.

---

## Usage

From any directory where you want to run the demo:

    chmod +x par2_single_bit_demo.sh
    ./par2_single_bit_demo.sh

The script will:

- Work only on dummy files it creates (no existing files are touched).
- Print step-by-step log messages in English.
- Leave the resulting files in the current directory for inspection:
  - `dummy.bin`             – final data file after tests  
  - `dummy.bin.original`    – original copy of the data file  
  - `dummy_par2.par2`       – main PAR2 control file  
  - `dummy_par2.vol*.par2`  – extra recovery volumes (parity blocks)

---

## Step-by-Step Explanation

Below is what the script does conceptually.

### 1. Create a dummy file

    dd if=/dev/urandom of=dummy.bin bs=1K count=64 status=none
    cp dummy.bin dummy.bin.original

- `dummy.bin` – 64 KiB of random data.
- `dummy.bin.original` – a clean copy to compare against later.

### 2. Create a PAR2 set with 10% redundancy

    par2 create -r10 dummy_par2 dummy.bin

- `-r10` means about 10% recovery data relative to the file size.
- par2 splits `dummy.bin` into fixed-size blocks and creates recovery blocks.
- The command prints things like:
  - block size,
  - number of data blocks,
  - number of recovery blocks.

Example (your exact numbers may differ):

    Source block count: 1821
    Recovery block count: 182

### 3. Verify (no corruption yet)

    par2 verify dummy_par2.par2

par2 scans `dummy.bin` and the PAR2 volumes.

At this point everything is intact, so you should see something like:

    All files are correct, repair is not required.

### 4. Introduce a single-bit error

The script uses Python to flip one bit in one byte:

    filename = "dummy.bin"
    idx = 123  # byte index to corrupt

    with open(filename, "rb") as f:
        data = bytearray(f.read())

    print(f"Original byte at index {idx}: 0x{data[idx]:02x}")
    data[idx] ^= 0x01  # flip the lowest bit
    print(f"Corrupted byte at index {idx}: 0x{data[idx]:02x}")

    with open(filename, "wb") as f:
        f.write(data)

Now `dummy.bin` differs from the original by exactly one bit.

### 5. Verify after single-bit corruption

    par2 verify dummy_par2.par2

Typical output:

    Target: "dummy.bin" - damaged. Found 1820 of 1821 data blocks.
    ...
    Repair is required.
    You have 1820 out of 1821 data blocks available.
    You have 182 recovery blocks available.
    Repair is possible.
    You have an excess of 181 recovery blocks.
    1 recovery blocks will be used to repair.

Interpretation:

- par2 detected that one data block is no longer consistent.
- We still have 1820/1821 data blocks plus 182 recovery blocks.
- With 10% redundancy, this is easy to fix.

### 6. Repair the single-bit error

    par2 repair dummy_par2.par2

par2 uses one recovery block to reconstruct the broken data block and rewrites
`dummy.bin`.

Then we verify again:

    par2 verify dummy_par2.par2

You should see:

    All files are correct, repair is not required.

To prove it really matches the original byte-for-byte:

    cmp dummy.bin dummy.bin.original

The script checks this for you and prints:

    [OK] Repaired file is byte-identical to the original.

At this point we’ve shown:

> A tiny error (single bit) is detected and corrected using the parity data.

---

## Extra Demo: Damage Beyond 10% (Repair Fails)

Now we want to show the limit of par2:

> If more data is damaged than the available redundancy can cover,
> par2 can still detect the error, but it can’t fully repair it.

### 7. Heavy corruption: overwrite half the file

We know the file size is 64 KiB. The script overwrites 32 KiB (half) of
`dummy.bin` with zeros:

    BYTES_TO_CORRUPT=$(( (64 * 1024) / 2 ))  # 32 KiB
    dd if=/dev/zero of="$FILENAME" bs=1 count="$BYTES_TO_CORRUPT" conv=notrunc status=none

This destroys far more than 10% of the data blocks.

### 8. Verify after heavy corruption

    par2 verify dummy_par2.par2

You should now see output similar to:

    Target: "dummy.bin" - damaged.
    ...
    Repair is required.
    You have X out of 1821 data blocks available.
    You have 182 recovery blocks available.
    Repair is not possible.

The exact numbers may vary, but the key points are:

- par2 detects heavy damage, but
- reports that there are not enough recovery blocks to reconstruct all
  missing data blocks.

### 9. Attempt repair (expected to fail)

    par2 repair dummy_par2.par2

This should fail, and the script will interpret that as the expected result:

    [Expected] par2 repair reported that repair is not possible due to too much damage.

Now we have shown:

> par2 cannot magically fix arbitrary amounts of data loss.  
> It can only repair up to the amount of redundancy you created.

---

## Key Takeaways

- par2 uses Reed–Solomon error-correcting codes over fixed-size blocks.
- With `-r10` you get roughly 10% redundancy:
  - par2 can repair many small errors, as long as total damage ≤ about 10% of blocks.
  - If more than that is destroyed, it can still detect the damage, but cannot fully
    reconstruct the file.
- This script demonstrates both behaviors with:
  - a single-bit flip (fully repaired), and
  - a large overwrite (half the file) (detected but not recoverable).

> par2 is not a substitute for backups.  
> It protects against random corruption and some data loss, but:
> - It does not protect you from “rm -rf”, ransomware, or disk failure.
> - It works best in addition to proper backups (e.g. ZFS, RAID, off-site copies).

---

## Credits / Provenance

- Code and README were created for educational purposes by GitHub user
  `junjinyong`, with the assistance of an LLM (ChatGPT).
- You are welcome to reuse, modify, or extend this demo for your own learning,
  documentation, or teaching.

If you extend the script (for example, multiple files, different redundancy
levels, or integration with ZFS snapshots), consider adding your own notes to
this README as well.

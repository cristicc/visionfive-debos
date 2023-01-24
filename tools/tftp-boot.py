#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Copyright (C) 2023 Cristian Ciocaltea <cristian.ciocaltea@gmail.com>
#
# Utility script to automate booting Linux kernel from U-Boot using TFTP.

import argparse
import sys

import pexpect
import pexpect.fdpexpect
import serial

UBOOT_PROMPT = "VisionFive #"
UBOOT_ERROR_MSGS = [
    "Resetting CPU"
    "Must RESET board to recover"
    "TIMEOUT"
    "Retry count exceeded"
    "Retry time exceeded; starting again"
    "ERROR: The remote end did not respond in time."
    "File not found"
    "Bad Linux ARM64 Image magic!"
    "Wrong Ramdisk Image Format"
    "Ramdisk image is corrupt or invalid"
    "ERROR: Failed to allocate"
    "TFTP error: trying to overwrite reserved memory"
    "Bad Linux RISCV Image magic!"
    "Wrong Image Format for boot"
    "ERROR: Did not find a cmdline Flattened Device Tree"
    "ERROR: RD image overlaps OS image"
]

UBOOT_KERNEL_ADDR = "0x84000000"
UBOOT_DTB_ADDR = "0x88000000"
UBOOT_RAMDISK_ADDR = "0x88300000"

TFTP_SERVER_IP = "192.168.1.90"
LINUX_KERNEL_IMG_DIR = "linux/build/arch/riscv/boot"

LINUX_KERNEL_START_MSG = "Linux version [0-9]"
SHELL_PROMPT = "/ # "


def wait_uboot_prompt(con):
    print("> Waiting for U-Boot prompt..")

    top = 10
    for count in range(top):
        try:
            con.expect(UBOOT_PROMPT, timeout=5)
            return
        except pexpect.TIMEOUT:
            print()
            print("> Timeout waiting for U-Boot prompt (try=%d)" % count)
            con.sendline(" ")
        except Exception as e:
            print()
            print(
                "> Error waiting for U-Boot prompt (try=%d): %s" % (count, e)
            )

    raise Exception("Failed to get U-Boot prompt")


def wait_shell_prompt(con):
    print()
    print("> Waiting for Shell prompt..")
    con.expect(SHELL_PROMPT, timeout=60)


def send_uboot_cmd(con, cmd, cmd_expect=UBOOT_PROMPT):
    msgs = UBOOT_ERROR_MSGS.copy()
    msgs.insert(0, cmd_expect)

    try:
        con.sendline(cmd)

        res = con.expect(msgs)
        if res > 0:
            raise Exception("Unexpected response: %s" % con.match.group(0))

    except Exception as e:
        raise Exception("Command %s failed: %s" % (cmd, e))


def tftp_boot_linux(con):
    try:
        send_uboot_cmd(con, "setenv autoload no")
        send_uboot_cmd(con, "setenv initrd_high 0xffffffffffffffff")
        send_uboot_cmd(con, "setenv fdt_high 0xffffffffffffffff")
        send_uboot_cmd(con, "dhcp")
        send_uboot_cmd(con, f"setenv serverip {TFTP_SERVER_IP}")
        send_uboot_cmd(
            con,
            f"tftpboot {UBOOT_KERNEL_ADDR} {LINUX_KERNEL_IMG_DIR}/Image",
        )
        send_uboot_cmd(
            con,
            f"tftpboot {UBOOT_DTB_ADDR} {LINUX_KERNEL_IMG_DIR}"
            + "/dts/starfive/jh7100-starfive-visionfive-v1.dtb",
        )
        send_uboot_cmd(
            con, f"tftpboot {UBOOT_RAMDISK_ADDR} ramdisk/rootfs.cpio.gz.uboot"
        )
        send_uboot_cmd(
            con,
            "setenv bootargs"
            + " 'console=ttyS0,115200n8 root=/dev/ram0"
            + " console_msg_format=syslog earlycon ip=dhcp ip=dhcp'",
        )
        send_uboot_cmd(
            con,
            f"booti {UBOOT_KERNEL_ADDR} {UBOOT_RAMDISK_ADDR} {UBOOT_DTB_ADDR}",
            LINUX_KERNEL_START_MSG
        )

    except Exception as e:
        print()
        print("> Error communicating with U-Boot: %s" % e)
        raise Exception("TFTP boot failed")


parser = argparse.ArgumentParser(
    description="Utility to automate booting Linux via U-Boot TFTP."
)

parser.add_argument("tty", help="Serial console device")
parser.add_argument(
    "baud",
    help="The serial port baud rate (default 115200)",
    nargs="?",
    default="115200",
)

args = parser.parse_args()

ser = serial.Serial(
    port=args.tty,
    baudrate=args.baud,
    stopbits=serial.STOPBITS_ONE,
    bytesize=serial.EIGHTBITS,
)

print("Connecting to " + args.tty + " @" + args.baud)

with pexpect.fdpexpect.fdspawn(
    ser, timeout=60, encoding="utf-8", logfile=sys.stdout
) as con:
    wait_uboot_prompt(con)
    tftp_boot_linux(con)
    wait_shell_prompt(con)

print
print("> Done")

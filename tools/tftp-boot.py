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


def send_cmd(con, cmd):
    try:
        con.sendline(cmd)

        res = con.expect(
            [
                UBOOT_PROMPT,
                "Resetting CPU",
                "Must RESET board to recover",
                "TIMEOUT",
                "Retry count exceeded",
                "Retry time exceeded; starting again",
                "File not found",
                "Wrong Ramdisk Image Format",
                "Ramdisk image is corrupt or invalid",
                "TFTP error: trying to overwrite reserved memory",
                "Bad Linux RISCV Image magic!",
                "Wrong Image Format for boot",
                "ERROR: Failed to allocate",
                "ERROR: The remote end did not respond in time.",
                "ERROR: Did not find a cmdline Flattened Device Tree",
                "ERROR: RD image overlaps OS image",
            ]
        )

        if res > 0:
            raise Exception("Unexpected response: %s" % con.match.group(0))

    except Exception as e:
        raise Exception("Command %s failed: %s" % (cmd, e))


def tftp_boot_linux(con):
    try:
        send_cmd(con, "setenv autoload no")
        send_cmd(con, "setenv initrd_high 0xffffffffffffffff")
        send_cmd(con, "setenv fdt_high 0xffffffffffffffff")
        send_cmd(con, "dhcp")
        send_cmd(con, "setenv serverip 192.168.1.90")
        send_cmd(
            con, "tftpboot 0x84000000 linux/build/arch/riscv/boot/Image"
        )
        send_cmd(
            con,
            "tftpboot 0x88000000 linux/build/arch/riscv/boot/dts/starfive/jh7100-starfive-visionfive-v1.dtb",
        )
        send_cmd(con, "tftpboot 0x88300000 ramdisk/rootfs.cpio.gz.uboot")
        send_cmd(
            con,
            "setenv bootargs"
            + " 'console=ttyS0,115200n8 root=/dev/ram0"
            + " console_msg_format=syslog earlycon ip=dhcp ip=dhcp'",
        )
        send_cmd(con, "booti 0x84000000 0x88300000 0x88000000")

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
    ser.close()

print
print("== Done! ==")

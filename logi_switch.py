#!/usr/bin/env python3
"""Switch a Logitech MX Keys + MX Master to the same Easy-Switch channel at once.

Usage:
  logi_switch.py 1|2|3     switch both devices to channel 1, 2 or 3
  logi_switch.py --status  show which channel each device is on (no switching)

Talks HID++ 2.0 over Bluetooth: looks up the CHANGE_HOST feature (0x1814)
on each device, then calls setCurrentHost.
"""
import ctypes
import sys
import hid

# Use the C library directly: on macOS the wrapper's open_path fails, and
# exclusive mode must be off since the OS is already using these devices.
lib = ctypes.CDLL(hid.__file__)
lib.hid_open_path.restype = ctypes.c_void_p
lib.hid_open_path.argtypes = [ctypes.c_char_p]
lib.hid_write.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
lib.hid_read_timeout.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_int]
lib.hid_close.argtypes = [ctypes.c_void_p]
lib.hid_darwin_set_open_exclusive(0)

LOGITECH = 0x046D
HIDPP_USAGE_PAGE = 0xFF43
DEVICES = {
    0xB35B: "MX Keys",
    0xB034: "MX Master 3S",
    0xB023: "MX Master 3",
}
LONG_REPORT = 0x11
BLE_DEVICE_INDEX = 0xFF
SW_ID = 0x0A
FEATURE_CHANGE_HOST = 0x1814


def request(dev, feature_index, function, params=b"", expect_reply=True):
    msg = bytes([LONG_REPORT, BLE_DEVICE_INDEX, feature_index, (function << 4) | SW_ID]) + params
    lib.hid_write(dev, msg.ljust(20, b"\x00"), 20)
    if not expect_reply:
        return None
    for _ in range(20):
        buf = ctypes.create_string_buffer(20)
        if lib.hid_read_timeout(dev, buf, 20, 500) <= 0:
            break
        reply = buf.raw
        if reply[2] == 0xFF:  # HID++ error report
            raise RuntimeError(f"HID++ error 0x{reply[5]:02x}")
        if reply[2] == feature_index and reply[3] == (function << 4) | SW_ID:
            return reply[4:]
    raise TimeoutError("no reply from device")


def change_host_index(dev):
    index = request(dev, 0x00, 0, FEATURE_CHANGE_HOST.to_bytes(2, "big"))[0]
    if index == 0:
        raise RuntimeError("device does not support CHANGE_HOST")
    return index


def open_devices():
    found = []
    for info in hid.enumerate(LOGITECH):
        name = DEVICES.get(info["product_id"])
        if name and info["usage_page"] == HIDPP_USAGE_PAGE:
            dev = lib.hid_open_path(info["path"])
            if dev:
                found.append((name, dev))
            else:
                print(f"{name}: could not open")
    return found


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg not in ("1", "2", "3", "--status"):
        sys.exit(__doc__)

    devices = open_devices()
    if not devices:
        sys.exit("No MX Keys / MX Master connected to this machine.")

    for name, dev in devices:
        try:
            index = change_host_index(dev)
            if arg == "--status":
                hosts, current = request(dev, index, 0)[:2]
                print(f"{name}: on channel {current + 1} of {hosts}")
            else:
                request(dev, index, 1, bytes([int(arg) - 1]), expect_reply=False)
                print(f"{name}: switched to channel {arg}")
        except Exception as e:
            print(f"{name}: failed ({e})")
        finally:
            lib.hid_close(dev)


if __name__ == "__main__":
    main()

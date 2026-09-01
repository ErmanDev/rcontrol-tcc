"""CPython checks for loader-bucket firmware (mocked MicroPython machine)."""

from __future__ import annotations

import importlib.util
import sys
import time
import types
import unittest
from pathlib import Path


def _load_firmware():
    if not hasattr(time, "sleep_ms"):
        time.sleep_ms = lambda ms: None
        time.sleep_us = lambda us: None
        time.ticks_ms = lambda: 0
        time.ticks_us = lambda: 0
        time.ticks_diff = lambda a, b: a - b

    machine = types.ModuleType("machine")

    class Pin:
        OUT = 1
        IN = 0

        def __init__(self, n, *args, **kwargs):
            self.n = n
            self._value = 0

        def value(self, v=None):
            if v is None:
                return self._value
            self._value = v

    class PWM:
        def __init__(self, pin):
            self.pin = pin
            self._freq = None
            self.duty = None

        def freq(self, f):
            self._freq = f

        def duty_u16(self, d):
            self.duty = d

    class UART:
        def __init__(self, *args, **kwargs):
            pass

    machine.Pin = Pin
    machine.PWM = PWM
    machine.UART = UART
    sys.modules["machine"] = machine

    path = Path(__file__).resolve().parents[1] / "pico_w" / "main_bluetooth.py"
    spec = importlib.util.spec_from_file_location("main_bluetooth", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


FW = _load_firmware()


class LoaderFirmwareTest(unittest.TestCase):
    def test_pins_are_right_header_gp16_gp17(self):
        self.assertEqual(FW.LOADER_SERVO_1_PIN, 16)
        self.assertEqual(FW.LOADER_SERVO_2_PIN, 17)
        # Existing drive / sensor pins stay put.
        self.assertEqual(FW.UART_TX, 0)
        self.assertEqual(FW.UART_RX, 1)
        self.assertEqual(FW.ULTRASONIC_ECHO, 2)
        self.assertEqual(FW.ULTRASONIC_TRIGGER, 3)
        self.assertEqual(FW.PWM_ENABLE_1, 6)
        self.assertEqual(FW.PWM_ENABLE_2, 7)
        self.assertEqual(FW.MOTOR_1, 10)
        self.assertEqual(FW.MOTOR_4, 13)
        self.assertEqual(FW.SERVO_PIN, 15)

    def test_positional_duty_clamps_0_180(self):
        self.assertEqual(FW._positional_servo_duty_u16(0), 1950)
        self.assertEqual(FW._positional_servo_duty_u16(180), 7803)
        self.assertEqual(FW._positional_servo_duty_u16(-40), 1950)
        self.assertEqual(FW._positional_servo_duty_u16(200), 7803)
        mid = FW._positional_servo_duty_u16(90)
        self.assertGreater(mid, 1950)
        self.assertLess(mid, 7803)

    def test_boot_is_down_and_servos_are_mirrored(self):
        self.assertTrue(FW.LOADER_SERVO_2_INVERT)
        self.assertEqual(FW.LOADER_DOWN_ANGLE, 90)
        self.assertEqual(FW.LOADER_UP_ANGLE, 150)
        self.assertLess(abs(FW.LOADER_UP_ANGLE - FW.LOADER_DOWN_ANGLE), 90)

        bucket = FW.LoaderBucket()
        self.assertFalse(bucket._up)
        self.assertEqual(bucket._pwm1._freq, 50)
        self.assertEqual(bucket._pwm2._freq, 50)
        # Rest pose is ~90° on both horns (180-90 == 90) — the photo, not UP.
        down_duty = FW._positional_servo_duty_u16(FW.LOADER_DOWN_ANGLE)
        self.assertEqual(bucket._pwm1.duty, down_duty)
        self.assertEqual(bucket._pwm2.duty, down_duty)

        bucket.up()
        self.assertTrue(bucket._up)
        up1 = FW._positional_servo_duty_u16(FW.LOADER_UP_ANGLE)
        up2 = FW._positional_servo_duty_u16(180 - FW.LOADER_UP_ANGLE)
        self.assertEqual(bucket._pwm1.duty, up1)
        self.assertEqual(bucket._pwm2.duty, up2)
        self.assertNotEqual(up1, up2)

    def test_loader_commands_work_in_automatic(self):
        motors = FW.Motors()
        ultra = FW.Ultrasonic()
        scanner = FW.ServoScanner(FW.SERVO_PIN)
        loader = FW.LoaderBucket()
        mower = FW.Mower(motors, ultra, scanner, loader)
        mower.set_mode("AUTOMATIC")
        self.assertEqual(mower.mode, "AUTOMATIC")

        mower.handle_line("LOADER|UP")
        self.assertTrue(loader._up)
        self.assertEqual(mower.mode, "AUTOMATIC")

        mower.handle_line("S")
        self.assertFalse(loader._up)
        self.assertEqual(mower.mode, "MANUAL")


if __name__ == "__main__":
    unittest.main()

"""Ultrasonic calibration / pin-check script for Raspberry Pi Pico.

Use this file alone on the Pico to verify:
1) Trigger/Echo pins are correct
2) Sensor is returning stable distance values

How to run (Thonny):
- Open this file
- Edit TRIGGER_PIN / ECHO_PIN below
- Save to Pico and run
"""

import time
from machine import Pin

# -------------------------
# User configuration
# -------------------------
TRIGGER_PIN = 3
ECHO_PIN = 2

ULTRASONIC_TIMEOUT_US = 30000
SAMPLE_COUNT = 7
SAMPLE_GAP_MS = 60
LOOP_DELAY_MS = 500

# Optional: set True to probe multiple echo pins quickly.
RUN_ECHO_PROBE = True
CANDIDATE_ECHO_PINS = [2, 3, 4, 5, 14, 15, 16, 17, 18, 19, 20, 21]


def _median(values):
    vals = sorted(values)
    n = len(vals)
    if n == 0:
        return None
    mid = n // 2
    if n % 2:
        return vals[mid]
    return (vals[mid - 1] + vals[mid]) / 2.0


class UltrasonicTester:
    def __init__(self, trig_pin, echo_pin):
        self.trig_pin_num = trig_pin
        self.echo_pin_num = echo_pin
        self.trigger = Pin(trig_pin, Pin.OUT)
        self.echo = Pin(echo_pin, Pin.IN)
        self.trigger.value(0)

    def measure_once(self):
        """Returns (distance_cm, status_string)."""
        self.trigger.value(0)
        time.sleep_us(2)
        self.trigger.value(1)
        time.sleep_us(10)
        self.trigger.value(0)

        t0 = time.ticks_us()
        while self.echo.value() == 0:
            if time.ticks_diff(time.ticks_us(), t0) > ULTRASONIC_TIMEOUT_US:
                return None, "timeout_wait_rise"
        start = time.ticks_us()

        while self.echo.value() == 1:
            if time.ticks_diff(time.ticks_us(), start) > ULTRASONIC_TIMEOUT_US:
                return None, "timeout_wait_fall"
        end = time.ticks_us()

        pulse = time.ticks_diff(end, start)
        if pulse <= 0:
            return None, "invalid_pulse"

        distance_cm = (pulse * 0.0343) / 2.0
        return distance_cm, "ok"

    def measure_filtered(self, count=SAMPLE_COUNT):
        good = []
        errors = {}

        for _ in range(count):
            distance, status = self.measure_once()
            if status == "ok" and distance is not None:
                good.append(distance)
            else:
                errors[status] = errors.get(status, 0) + 1
            time.sleep_ms(SAMPLE_GAP_MS)

        return _median(good), good, errors


def probe_echo_pins(trigger_pin, candidates):
    """Try multiple echo pins and show which pins return valid distances."""
    print("\n=== Echo Pin Probe ===")
    print("Trigger pin fixed at GP{}".format(trigger_pin))
    print("Candidates:", candidates)
    print("----------------------")

    for echo_pin in candidates:
        tester = UltrasonicTester(trigger_pin, echo_pin)
        ok_count = 0
        for _ in range(4):
            d, status = tester.measure_once()
            if status == "ok" and d is not None and d < 600:
                ok_count += 1
            time.sleep_ms(30)
        print("GP{:>2} -> valid reads: {}/4".format(echo_pin, ok_count))
    print("======================\n")


def main():
    print("Ultrasonic calibration starting...")
    print("TRIG=GP{}, ECHO=GP{}".format(TRIGGER_PIN, ECHO_PIN))
    print("Place obstacle at known distances (e.g. 10cm, 20cm, 30cm).")
    print("Press Ctrl+C to stop.\n")

    if RUN_ECHO_PROBE:
        probe_echo_pins(TRIGGER_PIN, CANDIDATE_ECHO_PINS)

    tester = UltrasonicTester(TRIGGER_PIN, ECHO_PIN)

    while True:
        median_cm, good, errors = tester.measure_filtered()

        if median_cm is None:
            print("[NO VALID READ] errors={}".format(errors))
            print("Hint: check VCC/GND, TRIG/ECHO pins, and shared ground.\n")
        else:
            mn = min(good)
            mx = max(good)
            print(
                "distance={:.2f} cm | samples={} | min={:.2f} max={:.2f} | errors={}".format(
                    median_cm, len(good), mn, mx, errors
                )
            )
        time.sleep_ms(LOOP_DELAY_MS)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nUltrasonic calibration stopped.")

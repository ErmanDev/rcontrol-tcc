"""Servo calibration script for Raspberry Pi Pico (MicroPython).

Purpose:
- Verify the servo rotates on the configured GPIO pin.
- Tune angle limits to avoid binding/jitter.

Usage (Thonny):
1) Set SERVO_PIN correctly.
2) Save/run on Pico.
3) Watch motion and console output.
4) Press Ctrl+C to stop.
"""

import time
from machine import PWM, Pin

# Change if needed (from your old working code)
SERVO_PIN = 15

# 50 Hz is standard for hobby servos
SERVO_FREQ = 50

# Positional-servo duty range from your old code.
MIN_DUTY_U16 = 1950
MAX_DUTY_U16 = 7803

# Motion test parameters
LEFT_ANGLE = 150
CENTER_ANGLE = 90
RIGHT_ANGLE = 30
STEP_DELAY_MS = 700
SWEEP_STEP = 5
SWEEP_DELAY_MS = 25


def angle_to_duty_u16(angle):
    angle = max(0, min(180, int(angle)))
    return int(angle * (MAX_DUTY_U16 - MIN_DUTY_U16) / 180 + MIN_DUTY_U16)


def set_angle(pwm, angle):
    duty = angle_to_duty_u16(angle)
    pwm.duty_u16(duty)
    print("angle={:>3} duty_u16={}".format(int(angle), duty))


def move_triplet(pwm):
    """Center-first sequence for quick verification."""
    for angle in (CENTER_ANGLE, LEFT_ANGLE, CENTER_ANGLE, RIGHT_ANGLE, CENTER_ANGLE):
        set_angle(pwm, angle)
        time.sleep_ms(STEP_DELAY_MS)


def sweep(pwm, start, end, step):
    if start <= end:
        a = start
        while a <= end:
            set_angle(pwm, a)
            time.sleep_ms(SWEEP_DELAY_MS)
            a += step
    else:
        a = start
        while a >= end:
            set_angle(pwm, a)
            time.sleep_ms(SWEEP_DELAY_MS)
            a -= step


def main():
    print("Servo calibration starting...")
    print("SERVO_PIN=GP{}".format(SERVO_PIN))
    print("Duty range: {}..{}".format(MIN_DUTY_U16, MAX_DUTY_U16))
    print("Press Ctrl+C to stop.\n")

    pwm = PWM(Pin(SERVO_PIN))
    pwm.freq(SERVO_FREQ)
    set_angle(pwm, CENTER_ANGLE)
    time.sleep_ms(700)

    try:
        while True:
            print("[Triplet test] CENTER -> LEFT -> CENTER -> RIGHT -> CENTER")
            move_triplet(pwm)

            print("[Sweep test] CENTER -> LEFT")
            sweep(pwm, CENTER_ANGLE, LEFT_ANGLE, SWEEP_STEP)
            print("[Sweep test] LEFT -> CENTER")
            sweep(pwm, LEFT_ANGLE, CENTER_ANGLE, SWEEP_STEP)
            print("[Sweep test] CENTER -> RIGHT")
            sweep(pwm, CENTER_ANGLE, RIGHT_ANGLE, SWEEP_STEP)
            print("[Sweep test] RIGHT -> CENTER")
            sweep(pwm, RIGHT_ANGLE, CENTER_ANGLE, SWEEP_STEP)

            print("---- cycle done ----\n")
            time.sleep_ms(500)
    finally:
        # Hold center on exit for safety.
        set_angle(pwm, CENTER_ANGLE)
        time.sleep_ms(200)
        pwm.deinit()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nServo calibration stopped.")

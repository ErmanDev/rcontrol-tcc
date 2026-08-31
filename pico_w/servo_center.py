"""Center servo helper for mechanical alignment before mounting ultrasonic.

Run this script on Pico to move servo to center and hold position.
"""

import time
from machine import PWM, Pin

SERVO_PIN = 15
SERVO_FREQ = 50

# Use same mapping as your project scripts.
MIN_DUTY_U16 = 1950
MAX_DUTY_U16 = 7803
CENTER_ANGLE = 90


def angle_to_duty_u16(angle):
    angle = max(0, min(180, int(angle)))
    return int(angle * (MAX_DUTY_U16 - MIN_DUTY_U16) / 180 + MIN_DUTY_U16)


def main():
    pwm = PWM(Pin(SERVO_PIN))
    pwm.freq(SERVO_FREQ)

    duty = angle_to_duty_u16(CENTER_ANGLE)
    pwm.duty_u16(duty)

    print("Servo centered.")
    print("SERVO_PIN=GP{}".format(SERVO_PIN))
    print("CENTER_ANGLE={}".format(CENTER_ANGLE))
    print("duty_u16={}".format(duty))
    print("Keep this script running while mounting the ultrasonic.")
    print("Press Ctrl+C when done.")

    try:
        while True:
            # Keep holding center.
            time.sleep_ms(500)
    except KeyboardInterrupt:
        print("\nStopped. Keeping center briefly...")
        time.sleep_ms(300)
        pwm.deinit()


if __name__ == "__main__":
    main()

"""Smart Mower firmware (Bluetooth UART + servo/ultrasonic automatic mode).

Copy this file onto the Pico W as main.py (Thonny: Save copy to Pico).
MicroPython boots main.py.

Loader bucket: two positional SG90s on the same hinge (not 360°).
  LEFT  = GP16 (user marked 16)  — logical angle
  RIGHT = GP17 (user marked 17)  — mirrored 180-angle so the pair does not fight
  orange = signal, red = 5V shared, brown = GND to physical pin 23.
  Default rest 90 so the bucket is NOT up at boot; invert still on.
  Down 90, Up 170 (~80° lift from rest, off the end-stop). PWM eases 2° / 20ms for UP/DOWN.
  At rest both servos are 90 (180-90=90) so the bucket stays flat.
  At UP: GP16=170, GP17=10 (180-170).
  Live cal (no sweep): LOADER|ANGLE|<n>, LOADER|16|<n>, LOADER|17|<n>.
"""

import sys
import time
from machine import PWM, Pin, UART

PWM_ENABLE_1 = 6
PWM_ENABLE_2 = 7
MOTOR_1 = 10
MOTOR_2 = 11
MOTOR_3 = 12
MOTOR_4 = 13
ULTRASONIC_TRIGGER = 3
ULTRASONIC_ECHO = 2
SERVO_PIN = 15
SERVO_MIN_DUTY_U16 = 1950
SERVO_MAX_DUTY_U16 = 7803

# GPIO map (do not reuse left-header pins for the loader):
#   GP0/GP1   UART TX/RX
#   GP2       ultrasonic echo
#   GP3       ultrasonic trigger
#   GP6/GP7   motor PWM enables
#   GP10–GP13 motors
#   GP15      ultrasonic scanner servo
# Loader bucket uses the RIGHT header only (physical 21–40):
#   GP16 (physical 21)  LEFT loader servo  — user labeled 16
#   GP17 (physical 22)  RIGHT loader servo — user labeled 17
# Positional hobby servos at 50 Hz — not continuous-rotation 360° units.
LOADER_SERVO_1_PIN = 16  # left, user marked 16
LOADER_SERVO_2_PIN = 17  # right, user marked 17
# Default rest 90 so the bucket is NOT up at boot; invert still on.
# At rest both servos are 90 (180-90=90) so the bucket stays flat.
# Boot, LOADER|DOWN, STOP, and BT connect all go here.
LOADER_DOWN_ANGLE = 90  # rest / default / photo-level bucket
# Prefer 170 so we stay off the end-stop: ~90–110° of lift from rest. 90+80=170.
# Not 180. Not 360. Not back to rest=0.
LOADER_UP_ANGLE = 170  # GP16=170, GP17=10 at UP. Invert still on.
# RIGHT servo (GP17) is on the opposite side of the same hinge, so it is mirrored.
# Invert on GP17 is what stops them fighting: that pin gets 180-angle each step.
# If the bucket twists instead of pivoting, set this False (or swap the plugs).
# At DOWN: GP16=90, GP17=90. At UP: GP16=170, GP17=10 (180-170).
LOADER_SERVO_2_INVERT = True  # right servo is mirrored; GP17 gets 180-angle so the pair does not fight
# Ease both horns together. Do not jump PWM in one shot (slams / fights).
LOADER_STEP_DEG = 2
LOADER_STEP_DELAY_MS = 20

PWM_FREQ_HZ = 1000
INITIAL_SPEED = 25000
# Separate automatic speeds: slower travel, stronger turns for full 90°.
AUTO_TRAVEL_SPEED = 42000
# Higher turn PWM so 90° completes under load.
AUTO_TURN_SPEED = 62800
MIN_SPEED = 0
MAX_SPEED = 65535
OBSTACLE_THRESHOLD_CM = 30.0
SIDE_WALL_THRESHOLD_CM = 20.0
ULTRASONIC_TIMEOUT_US = 30000
ULTRASONIC_FRONT_SAMPLES = 5
ULTRASONIC_SIDE_SAMPLES = 3
NO_ECHO_IS_OBSTACLE = True
OBSTACLE_CONFIRM_READS = 2
# Keep turns near 90° with stronger turn speed (was ~110°, trim time).
TURN_90_TIME = 0.37
# First 90° after backup is under extra load near the wall.
TURN_1_TIME = 0.48
ROW_SHIFT_TIME = 0.3
BACKUP_TIME = 0.35
BOTH_BLOCKED_BACKUP_TIME = 1.5
SERVO_SETTLE_MS = 300
SERVO_STEP_DEG = 2
SERVO_STEP_DELAY_MS = 28
LOOP_MS = 10

UART_ID = 0
UART_BAUD = 9600
UART_TX = 0
UART_RX = 1


class Motors:
    def __init__(self):
        self._m1 = Pin(MOTOR_1, Pin.OUT)
        self._m2 = Pin(MOTOR_2, Pin.OUT)
        self._m3 = Pin(MOTOR_3, Pin.OUT)
        self._m4 = Pin(MOTOR_4, Pin.OUT)
        self._pwm1 = PWM(Pin(PWM_ENABLE_1))
        self._pwm2 = PWM(Pin(PWM_ENABLE_2))
        self._pwm1.freq(PWM_FREQ_HZ)
        self._pwm2.freq(PWM_FREQ_HZ)
        self._duty = INITIAL_SPEED
        self.set_speed(self._duty)
        self.stop()

    def set_speed(self, duty):
        duty = max(MIN_SPEED, min(MAX_SPEED, int(duty)))
        self._duty = duty
        self._pwm1.duty_u16(duty)
        self._pwm2.duty_u16(duty)
        return duty

    def _drive(self, left_a, left_b, right_a, right_b):
        self._m1.value(left_a)
        self._m2.value(left_b)
        self._m3.value(right_a)
        self._m4.value(right_b)

    def move_forward(self):
        # Calibrated to match current wiring:
        # app FORWARD previously produced left-turn behavior.
        self._drive(0, 1, 1, 0)

    def move_backward(self):
        # Calibrated to match current wiring:
        # app BACKWARD previously produced right-turn behavior.
        self._drive(1, 0, 0, 1)

    def turn_left(self):
        # Calibrated to match current wiring.
        self._drive(1, 0, 1, 0)

    def turn_right(self):
        # Calibrated to match current wiring.
        self._drive(0, 1, 0, 1)

    def stop(self):
        self._drive(0, 0, 0, 0)


class Ultrasonic:
    def __init__(self):
        self._trigger = Pin(ULTRASONIC_TRIGGER, Pin.OUT)
        self._echo = Pin(ULTRASONIC_ECHO, Pin.IN)
        self._trigger.value(0)

    def measure_cm(self):
        self._trigger.value(0)
        time.sleep_us(2)
        self._trigger.value(1)
        time.sleep_us(10)
        self._trigger.value(0)
        t0 = time.ticks_us()
        while self._echo.value() == 0:
            if time.ticks_diff(time.ticks_us(), t0) > ULTRASONIC_TIMEOUT_US:
                return None
        start = time.ticks_us()
        while self._echo.value() == 1:
            if time.ticks_diff(time.ticks_us(), start) > ULTRASONIC_TIMEOUT_US:
                return None
        end = time.ticks_us()
        duration = time.ticks_diff(end, start)
        if duration <= 0:
            return None
        return (duration * 0.0343) / 2.0

    def measure_filtered_cm(self, samples=ULTRASONIC_FRONT_SAMPLES, delay_ms=10):
        """Median of valid samples; returns None if all samples fail."""
        values = []
        for _ in range(max(1, int(samples))):
            distance = self.measure_cm()
            if distance is not None:
                values.append(distance)
            if delay_ms > 0:
                time.sleep_ms(delay_ms)
        if not values:
            return None
        values.sort()
        return values[len(values) // 2]


class ServoScanner:
    LEFT_ANGLE = 150
    CENTER_ANGLE = 90
    RIGHT_ANGLE = 30

    def __init__(self, pin):
        self._pwm = PWM(Pin(pin))
        self._pwm.freq(50)
        self._current_angle = self.CENTER_ANGLE
        self.set_angle(self.CENTER_ANGLE)
        time.sleep_ms(SERVO_SETTLE_MS)

    def _angle_to_duty(self, angle):
        angle = max(0, min(180, int(angle)))
        # Match your old positional-servo formula:
        # duty = int(angle * (7803 - 1950) / 180 + 1950)
        return int(
            angle * (SERVO_MAX_DUTY_U16 - SERVO_MIN_DUTY_U16) / 180
            + SERVO_MIN_DUTY_U16
        )

    def set_angle(self, angle):
        angle = max(0, min(180, int(angle)))
        self._pwm.duty_u16(self._angle_to_duty(angle))
        self._current_angle = angle

    def move_smooth(self, target_angle, step_deg=SERVO_STEP_DEG, step_delay_ms=SERVO_STEP_DELAY_MS):
        target_angle = max(0, min(180, int(target_angle)))
        step_deg = max(1, int(step_deg))
        step = step_deg if target_angle >= self._current_angle else -step_deg
        for angle in range(self._current_angle, target_angle, step):
            self.set_angle(angle)
            time.sleep_ms(step_delay_ms)
        self.set_angle(target_angle)

    def scan_sides(self, ultrasonic):
        self.move_smooth(self.LEFT_ANGLE)
        time.sleep_ms(SERVO_SETTLE_MS)
        left = ultrasonic.measure_filtered_cm(samples=ULTRASONIC_SIDE_SAMPLES, delay_ms=8)
        self.move_smooth(self.RIGHT_ANGLE)
        time.sleep_ms(SERVO_SETTLE_MS)
        right = ultrasonic.measure_filtered_cm(samples=ULTRASONIC_SIDE_SAMPLES, delay_ms=8)
        self.move_smooth(self.CENTER_ANGLE)
        time.sleep_ms(SERVO_SETTLE_MS)
        return left, right


def _positional_servo_duty_u16(angle):
    """50 Hz positional hobby-servo duty. Angle is clamped to 0–180."""
    angle = max(0, min(180, int(angle)))
    return int(
        angle * (SERVO_MAX_DUTY_U16 - SERVO_MIN_DUTY_U16) / 180
        + SERVO_MIN_DUTY_U16
    )


class LoaderBucket:
    """Two positional hobby servos driven together (UP / DOWN, not 360°).

    LEFT (GP16) takes the logical angle. RIGHT (GP17) is inverted when
    LOADER_SERVO_2_INVERT is True (command 180-angle) so the pair does not
    fight. UP/DOWN ease in LOADER_STEP_DEG steps; live cal writes immediately.
    """

    def __init__(self, pin1=LOADER_SERVO_1_PIN, pin2=LOADER_SERVO_2_PIN):
        self._pwm1 = PWM(Pin(pin1))
        self._pwm2 = PWM(Pin(pin2))
        self._pwm1.freq(50)
        self._pwm2.freq(50)
        self._up = False
        # Boot rest pose: already at DOWN 90 so the bucket is NOT up at boot.
        # down() writes 90/90 (invert still on: 180-90=90). Does not sweep.
        self._angle = LOADER_DOWN_ANGLE
        self.down()
        time.sleep_ms(SERVO_SETTLE_MS)

    def _clamp_command_angle(self, angle):
        """Clamp to 0–180. 0 and 180 are allowed (mirrored rest / end)."""
        return max(0, min(180, int(angle)))

    def _set_angle(self, angle):
        """Write one logical angle to both horns (invert GP17 each step)."""
        angle = self._clamp_command_angle(angle)
        # Invert on GP17 stops them fighting: right horn gets 180-angle.
        angle2 = (180 - angle) if LOADER_SERVO_2_INVERT else angle
        angle2 = self._clamp_command_angle(angle2)
        self._pwm1.duty_u16(_positional_servo_duty_u16(angle))
        self._pwm2.duty_u16(_positional_servo_duty_u16(angle2))
        self._angle = angle

    def set_linked_angle(self, angle):
        """Live cal: GP16=angle, GP17=180-angle if invert. No sweep."""
        self._set_angle(angle)

    def set_left_raw(self, angle):
        """Live cal: GP16 only. Last-angle follows left for later UP/DOWN."""
        angle = self._clamp_command_angle(angle)
        self._pwm1.duty_u16(_positional_servo_duty_u16(angle))
        self._angle = angle

    def set_right_raw(self, angle):
        """Live cal: GP17 only, RAW (do not invert). Last-angle stays GP16."""
        angle = self._clamp_command_angle(angle)
        self._pwm2.duty_u16(_positional_servo_duty_u16(angle))

    def _sweep_to(self, target_angle):
        """Ease both servos together from last commanded angle to target."""
        target_angle = self._clamp_command_angle(target_angle)
        last = self._angle
        if last == target_angle:
            self._set_angle(target_angle)
            return
        step_deg = max(1, int(LOADER_STEP_DEG))
        step = step_deg if target_angle >= last else -step_deg
        for angle in range(last, target_angle, step):
            self._set_angle(angle)
            time.sleep_ms(LOADER_STEP_DELAY_MS)
        self._set_angle(target_angle)

    def up(self):
        self._sweep_to(LOADER_UP_ANGLE)
        self._up = True
        print(
            "Loader -> UP GP{}+GP{} angle={} invert2={}".format(
                LOADER_SERVO_1_PIN,
                LOADER_SERVO_2_PIN,
                LOADER_UP_ANGLE,
                LOADER_SERVO_2_INVERT,
            )
        )

    def down(self):
        self._sweep_to(LOADER_DOWN_ANGLE)
        self._up = False
        print(
            "Loader -> DOWN GP{}+GP{} angle={} invert2={}".format(
                LOADER_SERVO_1_PIN,
                LOADER_SERVO_2_PIN,
                LOADER_DOWN_ANGLE,
                LOADER_SERVO_2_INVERT,
            )
        )


class ManualController:
    def __init__(self, motors):
        self._motors = motors

    def handle(self, command):
        if command == "FORWARD":
            self._motors.move_forward()
        elif command == "BACKWARD":
            self._motors.move_backward()
        elif command == "LEFT":
            self._motors.turn_left()
        elif command == "RIGHT":
            self._motors.turn_right()
        elif command == "STOP":
            self._motors.stop()
        else:
            raise ValueError("invalid command")


class AutomaticController:
    """Boustrophedon coverage guided by ultrasonic corners.

    On front/center obstacle:
      1) backup + stop
      2) slow left/right scan -> choose first 90° turn
         (left blocked -> RIGHT, right blocked -> LEFT)
         both blocked -> reverse 1.5s and rescan until one side is open
      3) turn exactly ~90° (not a half-circle)
      4) travel forward 1.0s
      5) stop + slow scan again
      6) second 90° turn based on scan
         (left blocked -> RIGHT, right blocked -> LEFT)
         both blocked -> reverse 1.5s and rescan until one side is open
      7) continue reverse row
    """

    STATE_FORWARD = "FORWARD"
    STATE_BACKUP = "BACKUP"
    STATE_SCAN_1 = "SCAN_1"
    STATE_TURN_1 = "TURN_1"
    STATE_SHIFT = "SHIFT"
    STATE_SCAN_2 = "SCAN_2"
    STATE_TURN_2 = "TURN_2"
    STATE_BOTH_BLOCKED_BACKUP = "BOTH_BLOCKED_BACKUP"

    def __init__(self, motors, ultrasonic, scanner):
        self._motors = motors
        self._ultrasonic = ultrasonic
        self._scanner = scanner
        self.state = self.STATE_FORWARD
        self.row_count = 0
        self._state_started = time.ticks_ms()
        self._turn1_dir = "RIGHT"
        self._turn2_dir = "RIGHT"
        self._resume_scan = self.STATE_SCAN_1
        self.running = False
        self._last_debug_ms = time.ticks_ms()
        self._obstacle_hits = 0
        self._saved_speed = INITIAL_SPEED

    def start(self):
        self.running = True
        self.row_count = 0
        self.state = self.STATE_FORWARD
        self._state_started = time.ticks_ms()
        self._turn1_dir = "RIGHT"
        self._turn2_dir = "RIGHT"
        self._resume_scan = self.STATE_SCAN_1
        self._obstacle_hits = 0
        self._saved_speed = self._motors._duty
        self._set_travel_speed()
        self._scanner.set_angle(self._scanner.CENTER_ANGLE)
        self._motors.move_forward()
        print(
            "AUTO started travel={} turn={}".format(
                AUTO_TRAVEL_SPEED, AUTO_TURN_SPEED
            )
        )

    def stop(self):
        self.running = False
        self._obstacle_hits = 0
        self._motors.stop()
        # Manual speed is restored by Mower when leaving AUTOMATIC.
        self._scanner.set_angle(self._scanner.CENTER_ANGLE)
        print("AUTO stopped")

    def _elapsed_s(self):
        return time.ticks_diff(time.ticks_ms(), self._state_started) / 1000.0

    def _enter(self, state):
        self.state = state
        self._state_started = time.ticks_ms()

    def _planned_turn(self):
        # Image pattern: end of L->R row prefers RIGHT; end of R->L prefers LEFT.
        return "RIGHT" if (self.row_count % 2 == 0) else "LEFT"

    def _set_travel_speed(self):
        self._motors.set_speed(AUTO_TRAVEL_SPEED)

    def _set_turn_speed(self):
        self._motors.set_speed(AUTO_TURN_SPEED)

    def _choose_turn_from_corners(self):
        """Slow left/right scan; turn away from the blocked side.

        Returns None when both sides are blocked so the caller can reverse
        and rescan until one side is open.
        """
        left, right = self._scanner.scan_sides(self._ultrasonic)
        print("Corner scan L/R:", left, right)
        left_blocked = left is None or left < SIDE_WALL_THRESHOLD_CM
        right_blocked = right is None or right < SIDE_WALL_THRESHOLD_CM

        if left_blocked and right_blocked:
            return None
        if left_blocked and not right_blocked:
            return "RIGHT"
        if right_blocked and not left_blocked:
            return "LEFT"
        return self._planned_turn()

    def _backup_and_rescan(self, resume_scan):
        print("Both sides blocked, reverse {:.1f}s then rescan".format(
            BOTH_BLOCKED_BACKUP_TIME
        ))
        self._resume_scan = resume_scan
        self._go_backward()
        self._enter(self.STATE_BOTH_BLOCKED_BACKUP)

    def _turn(self, direction):
        self._set_turn_speed()
        if direction == "LEFT":
            self._motors.turn_left()
        else:
            self._motors.turn_right()

    def _go_forward(self):
        self._set_travel_speed()
        self._motors.move_forward()

    def _go_backward(self):
        self._set_travel_speed()
        self._motors.move_backward()

    def tick(self, front_distance):
        if not self.running:
            return

        if front_distance is None:
            obstacle = NO_ECHO_IS_OBSTACLE
        else:
            obstacle = front_distance <= OBSTACLE_THRESHOLD_CM

        now = time.ticks_ms()
        if time.ticks_diff(now, self._last_debug_ms) >= 1000:
            self._last_debug_ms = now
            print(
                "AUTO state={} row={} plan={} front_cm={} obstacle={} hits={}".format(
                    self.state,
                    self.row_count,
                    self._planned_turn(),
                    front_distance,
                    obstacle,
                    self._obstacle_hits,
                )
            )

        # Only start a new sequence while mowing a straight row.
        if self.state == self.STATE_FORWARD and obstacle:
            self._obstacle_hits += 1
        elif self.state == self.STATE_FORWARD:
            self._obstacle_hits = 0

        if self.state == self.STATE_FORWARD and self._obstacle_hits >= OBSTACLE_CONFIRM_READS:
            print("Front obstacle, begin 90° + scan sequence:", front_distance)
            self._obstacle_hits = 0
            self._go_backward()
            self._enter(self.STATE_BACKUP)
            return

        if self.state == self.STATE_FORWARD:
            return

        if self.state == self.STATE_BACKUP and self._elapsed_s() >= BACKUP_TIME:
            self._motors.stop()
            self._enter(self.STATE_SCAN_1)
            return

        if self.state == self.STATE_SCAN_1:
            # Stopped scan for first 90° decision.
            self._turn1_dir = self._choose_turn_from_corners()
            if self._turn1_dir is None:
                self._backup_and_rescan(self.STATE_SCAN_1)
                return
            print("First 90° turn:", self._turn1_dir)
            self._turn(self._turn1_dir)
            self._enter(self.STATE_TURN_1)
            return

        if self.state == self.STATE_TURN_1 and self._elapsed_s() >= TURN_1_TIME:
            self._motors.stop()
            self._go_forward()
            self._enter(self.STATE_SHIFT)
            return

        if self.state == self.STATE_SHIFT and self._elapsed_s() >= ROW_SHIFT_TIME:
            # Exactly 1s forward, then stop and scan again.
            self._motors.stop()
            self._enter(self.STATE_SCAN_2)
            return

        if self.state == self.STATE_SCAN_2:
            self._turn2_dir = self._choose_turn_from_corners()
            if self._turn2_dir is None:
                self._backup_and_rescan(self.STATE_SCAN_2)
                return
            print("Second 90° turn:", self._turn2_dir)
            self._turn(self._turn2_dir)
            self._enter(self.STATE_TURN_2)
            return

        if self.state == self.STATE_BOTH_BLOCKED_BACKUP and self._elapsed_s() >= BOTH_BLOCKED_BACKUP_TIME:
            self._motors.stop()
            self._enter(self._resume_scan)
            return

        if self.state == self.STATE_TURN_2 and self._elapsed_s() >= TURN_90_TIME:
            self._motors.stop()
            self.row_count += 1
            self._go_forward()
            self._enter(self.STATE_FORWARD)
            print("Reverse row started:", self.row_count)


class Mower:
    MOVE_MAP = {
        "F": "FORWARD",
        "B": "BACKWARD",
        "L": "LEFT",
        "R": "RIGHT",
        "S": "STOP",
        "FORWARD": "FORWARD",
        "BACKWARD": "BACKWARD",
        "LEFT": "LEFT",
        "RIGHT": "RIGHT",
        "STOP": "STOP",
    }

    def __init__(self, motors, ultrasonic, scanner, loader):
        self.motors = motors
        self.ultrasonic = ultrasonic
        self.loader = loader
        self.manual = ManualController(motors)
        self.auto = AutomaticController(motors, ultrasonic, scanner)
        self.mode = "MANUAL"
        self.manual_speed = INITIAL_SPEED

    def emergency_stop(self):
        # Safe hopper first, then existing drive STOP / leave AUTOMATIC.
        self.loader.down()
        self.mode = "MANUAL"
        self.auto.stop()
        self.motors.set_speed(self.manual_speed)
        self.manual.handle("STOP")
        print("EMERGENCY STOP")

    def set_mode(self, mode):
        mode = mode.strip().upper()
        if mode == "MANUAL":
            self.mode = mode
            self.auto.stop()
            self.motors.set_speed(self.manual_speed)
            self.manual.handle("STOP")
            print("Mode -> MANUAL speed={}".format(self.manual_speed))
        elif mode == "AUTOMATIC":
            self.mode = mode
            self.manual.handle("STOP")
            self.auto.start()
            print("Mode -> AUTOMATIC")
        else:
            raise ValueError("invalid mode")

    def set_speed(self, speed):
        duty = self.motors.set_speed(int(speed))
        self.manual_speed = duty
        print("Speed ->", duty)
        return duty

    def handle_line(self, line):
        cmd = line.strip().upper()
        if not cmd:
            return
        if cmd == "MANUAL":
            self.set_mode("MANUAL")
            return
        if cmd == "AUTOMATIC":
            self.set_mode("AUTOMATIC")
            return
        if cmd.startswith("E|"):
            try:
                requested = int(cmd.split("|", 1)[1])
            except (ValueError, IndexError):
                print("Invalid speed command:", cmd)
                return
            # Always remember slider value for manual mode.
            self.manual_speed = max(MIN_SPEED, min(MAX_SPEED, requested))
            if self.mode == "AUTOMATIC":
                print("AUTO active; manual speed saved:", self.manual_speed)
                return
            self.motors.set_speed(self.manual_speed)
            print("Manual speed ->", self.manual_speed)
            return
        if cmd.startswith("LOADER|"):
            # Hopper is independent of drive; allowed in MANUAL and AUTOMATIC.
            parts = cmd.split("|")
            if len(parts) == 2:
                action = parts[1]
                if action == "UP":
                    self.loader.up()
                elif action == "DOWN":
                    self.loader.down()
                else:
                    print("Invalid loader command:", cmd)
                return
            if len(parts) == 3:
                target = parts[1]
                try:
                    angle = int(parts[2])
                except ValueError:
                    print("Invalid loader command:", cmd)
                    return
                if target == "16":
                    self.loader.set_left_raw(angle)
                elif target == "17":
                    self.loader.set_right_raw(angle)
                elif target == "ANGLE":
                    self.loader.set_linked_angle(angle)
                else:
                    print("Invalid loader command:", cmd)
                return
            print("Invalid loader command:", cmd)
            return

        mapped = self.MOVE_MAP.get(cmd)
        if mapped is None:
            print("Unknown command:", cmd)
            return
        if mapped == "STOP":
            self.emergency_stop()
            return
        if self.mode != "MANUAL":
            print("Manual command ignored while automatic mode is active")
            return
        self.manual.handle(mapped)

    def tick(self):
        if self.mode == "AUTOMATIC":
            # Only range while mowing a row. Timed backup/turn/shift
            # would overshoot if each loop waited on 5 ultrasonic samples.
            front_distance = None
            if self.auto.state == self.auto.STATE_FORWARD:
                front_distance = self.ultrasonic.measure_filtered_cm(
                    samples=ULTRASONIC_FRONT_SAMPLES,
                    delay_ms=10,
                )
            self.auto.tick(front_distance)


def init_uart():
    try:
        uart = UART(UART_ID, baudrate=UART_BAUD, tx=Pin(UART_TX), rx=Pin(UART_RX))
        print("Bluetooth UART ready @", UART_BAUD)
        return uart, b""
    except Exception as exc:
        print("UART unavailable:", exc)
        return None, b""


def poll_uart_lines(uart, buffer):
    if uart is None:
        return [], buffer
    try:
        if not uart.any():
            return [], buffer
        chunk = uart.read()
    except OSError:
        return [], buffer
    if not chunk:
        return [], buffer

    buffer += chunk
    lines = []
    while True:
        nl = buffer.find(b"\n")
        cr = buffer.find(b"\r")
        idx = min(x for x in (nl, cr) if x >= 0) if (nl >= 0 or cr >= 0) else -1
        if idx < 0:
            break
        line = buffer[:idx].decode().strip()
        buffer = buffer[idx + 1 :]
        if buffer[:1] in (b"\n", b"\r"):
            buffer = buffer[1:]
        if line:
            lines.append(line)
    if len(buffer) > 256:
        buffer = b""
    return lines, buffer


def main():
    print("Smart Mower Bluetooth firmware starting...")
    motors = Motors()
    ultrasonic = Ultrasonic()
    scanner = ServoScanner(SERVO_PIN)
    loader = LoaderBucket()
    mower = Mower(motors, ultrasonic, scanner, loader)
    uart, uart_buf = init_uart()

    while True:
        lines, uart_buf = poll_uart_lines(uart, uart_buf)
        for line in lines:
            mower.handle_line(line)
        mower.tick()
        time.sleep_ms(LOOP_MS)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Stopped")
        sys.exit(0)



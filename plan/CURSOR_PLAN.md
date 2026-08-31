# Smart Mower --- Cursor Development Plan

## 1. Project Overview

Build a mobile application for controlling a Raspberry Pi Pico W-based
smart mower.

The current Raspberry Pi Pico W firmware is written in MicroPython. It
currently communicates through UART at 9600 baud and controls four motor
outputs, two PWM enable pins, and an ultrasonic obstacle sensor.

The goal is to:

1.  Preserve the existing motor and automatic mowing behavior.
2.  Replace the UART command interface with Wi-Fi communication.
3.  Add a simple HTTP API to the Pico W.
4.  Build a Flutter mobile application that communicates with the Pico W
    over Wi-Fi.
5.  Keep autonomous mowing logic on the Pico W rather than moving it
    into the phone.
6.  Provide manual control, automatic mode, speed control, status
    monitoring, and an emergency STOP function.

------------------------------------------------------------------------

# 2. Existing Hardware Configuration

## GPIO assignments

  GPIO   Function
  ------ --------------------
  GP6    PWM Enable 1
  GP7    PWM Enable 2
  GP10   Motor 1
  GP11   Motor 2
  GP12   Motor 3
  GP13   Motor 4
  GP14   Ultrasonic Trigger
  GP15   Ultrasonic Echo

## Current PWM

-   Frequency: 1000 Hz
-   Initial duty cycle: 25000

## Ultrasonic sensor

The current obstacle threshold is:

``` text
12.7 cm
```

If an object is closer than 12.7 cm, the mower considers an obstacle
detected.

------------------------------------------------------------------------

# 3. Current Robot Behavior

## Manual commands

The current UART commands are:

  Command       Action
  ------------- -----------------------
  `F`           Forward
  `B`           Backward
  `R`           Turn right
  `L`           Turn left
  `S`           Stop
  `E|value`     Set motor speed
  `MANUAL`      Manual mode
  `AUTOMATIC`   Automatic mowing mode

Do not remove or change the behavior of these commands until the new
Wi-Fi API has been tested.

------------------------------------------------------------------------

# 4. Current Automatic Mowing Algorithm

The existing state machine is:

``` text
FORWARD
   |
   | obstacle detected
   v
BACKUP
   |
   v
TURN_1
   |
   v
SHIFT
   |
   v
TURN_2
   |
   v
FORWARD
```

Current timing:

``` text
TURN_90_TIME = 0.4 seconds
ROW_SHIFT_TIME = 0.5 seconds
BACKUP_TIME = 0.3 seconds
```

The automatic algorithm must remain on the Pico W.

The Flutter application should only start, stop, monitor, or configure
the mower.

------------------------------------------------------------------------

# 5. Target Architecture

``` text
                    ┌─────────────────────────┐
                    │      Flutter App        │
                    │                         │
                    │  Manual Control         │
                    │  Automatic Mode         │
                    │  Speed Control           │
                    │  Status                  │
                    │  Emergency STOP          │
                    └────────────┬────────────┘
                                 │
                              Wi-Fi
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │   Raspberry Pi Pico W   │
                    │                         │
                    │       HTTP API          │
                    │            │            │
                    │       Controller        │
                    │        /       \        │
                    │    Manual     Automatic │
                    │                         │
                    └──────────┬───────┬──────┘
                               │       │
                             Motors  Ultrasonic
```

------------------------------------------------------------------------

# 6. Development Rules for Cursor

Before modifying code:

-   Analyze the existing firmware.
-   Do not rewrite everything at once.
-   Preserve GPIO assignments.
-   Preserve motor direction logic.
-   Preserve automatic mowing behavior.
-   Preserve obstacle detection behavior.
-   Preserve existing timing values unless a bug is identified.
-   Keep hardware logic independent from networking.
-   Keep Flutter networking independent from Flutter UI.
-   Do not move autonomous decision-making into Flutter.
-   Make changes in small, testable phases.
-   After each phase, explain what changed and how to test it.

------------------------------------------------------------------------

# 7. Phase 1 --- Analyze Existing Pico W Code

### Cursor prompt

``` text
Analyze the existing Raspberry Pi Pico W MicroPython firmware.

Do not modify the code yet.

Identify:

1. GPIO pin assignments
2. Motor control logic
3. PWM speed control
4. Ultrasonic sensor behavior
5. Obstacle detection threshold
6. Manual mode commands
7. Automatic mowing state machine
8. UART communication
9. Blocking operations and delays
10. Safety behavior
11. Potential bugs
12. What needs to change to support Wi-Fi

The existing robot behavior must be preserved.

Produce a technical summary before making any changes.
```

### Acceptance criteria

-   Cursor understands every GPIO.
-   Cursor understands manual commands.
-   Cursor understands automatic mode.
-   Cursor understands obstacle detection.
-   No code has been changed yet.

------------------------------------------------------------------------

# 8. Phase 2 --- Refactor Pico W Firmware

Create this structure:

``` text
pico_w/
├── main.py
├── config.py
├── wifi.py
├── server.py
├── hardware/
│   ├── __init__.py
│   ├── motors.py
│   └── ultrasonic.py
└── controller/
    ├── __init__.py
    ├── manual.py
    └── automatic.py
```

### Responsibilities

## `config.py`

Store:

-   GPIO numbers
-   PWM frequency
-   initial speed
-   obstacle threshold
-   movement timings
-   Wi-Fi configuration

## `hardware/motors.py`

Contain:

-   motor initialization
-   `move_forward()`
-   `move_backward()`
-   `turn_left()`
-   `turn_right()`
-   `stop()`
-   speed/PWM control

## `hardware/ultrasonic.py`

Contain:

-   trigger/echo initialization
-   distance measurement
-   obstacle detection

## `controller/manual.py`

Handle manual commands.

## `controller/automatic.py`

Handle:

-   FORWARD
-   BACKUP
-   TURN_1
-   SHIFT
-   TURN_2
-   row counting
-   obstacle detection
-   automatic stop behavior

## `wifi.py`

Handle:

-   Wi-Fi connection
-   reconnect behavior
-   IP address reporting

## `server.py`

Handle:

-   HTTP server
-   API routing
-   request parsing
-   JSON responses

## `main.py`

Only coordinate:

``` text
initialize
   ↓
connect Wi-Fi
   ↓
initialize controllers
   ↓
run control loop
```

------------------------------------------------------------------------

# 9. Phase 3 --- Add Wi-Fi

The Pico W must connect to a 2.4 GHz Wi-Fi network.

Do not hard-code credentials directly into controller logic.

Use configuration values such as:

``` python
WIFI_SSID = "YOUR_WIFI"
WIFI_PASSWORD = "YOUR_PASSWORD"
```

Prefer a separate configuration file that can be excluded from source
control.

The Pico W should report:

-   connected/disconnected
-   IP address

Example startup output:

``` text
Smart Mower Starting...
Connecting to Wi-Fi...
Wi-Fi connected
IP: 192.168.x.x
HTTP server started
```

------------------------------------------------------------------------

# 10. Phase 4 --- Design the HTTP API

Use JSON responses.

## Health endpoint

``` text
GET /api/health
```

Example response:

``` json
{
  "status": "ok",
  "device": "smart-mower"
}
```

## Status endpoint

``` text
GET /api/status
```

Example:

``` json
{
  "mode": "MANUAL",
  "state": "STOPPED",
  "row_count": 0,
  "obstacle": false,
  "speed": 25000
}
```

## Manual control

``` text
POST /api/control
```

Request:

``` json
{
  "command": "FORWARD"
}
```

Supported commands:

``` text
FORWARD
BACKWARD
LEFT
RIGHT
STOP
```

## Mode

``` text
POST /api/mode
```

Manual:

``` json
{
  "mode": "MANUAL"
}
```

Automatic:

``` json
{
  "mode": "AUTOMATIC"
}
```

## Speed

``` text
POST /api/speed
```

Request:

``` json
{
  "speed": 25000
}
```

Validate the speed value before applying it to PWM.

------------------------------------------------------------------------

# 11. Phase 5 --- API Safety

Implement server-side validation.

Invalid commands must not activate motors.

Invalid speed values must not be passed directly to PWM.

If an API request is malformed:

``` text
HTTP 400
```

If an unknown endpoint is requested:

``` text
HTTP 404
```

If an unexpected internal error occurs:

``` text
HTTP 500
```

The STOP command must always be handled safely.

------------------------------------------------------------------------

# 12. Phase 6 --- Manual Mode Safety

Manual control should work like:

``` text
Flutter
   ↓
POST /api/control
   ↓
Pico validates command
   ↓
Motor controller
```

The Flutter app must never directly control GPIO.

The Pico W remains responsible for actual motor activation.

------------------------------------------------------------------------

# 13. Phase 7 --- Automatic Mode

Automatic mode must remain entirely on the Pico W.

When the Flutter app sends:

``` json
{
  "mode": "AUTOMATIC"
}
```

the Pico should:

1.  Reset mowing state.
2.  Reset row count.
3.  Stop safely.
4.  Start the automatic state machine.

The Pico should continue operating even if the Flutter screen is
changed.

If the design requires autonomous operation without the phone, the mower
should not depend on continuous HTTP requests from Flutter.

------------------------------------------------------------------------

# 14. Phase 8 --- Emergency STOP

Implement an obvious STOP button in Flutter.

The button should call:

``` text
POST /api/control
```

with:

``` json
{
  "command": "STOP"
}
```

The Pico must immediately execute:

``` python
stop()
```

The STOP behavior should also exit/disable automatic movement when
appropriate.

Do not rely only on the Flutter UI to stop the motors.

------------------------------------------------------------------------

# 15. Phase 9 --- Create Flutter Application

Create:

``` text
mobile/
├── lib/
│   ├── main.dart
│   │
│   ├── models/
│   │   └── mower_status.dart
│   │
│   ├── services/
│   │   └── pico_service.dart
│   │
│   ├── screens/
│   │   ├── home_screen.dart
│   │   ├── manual_screen.dart
│   │   ├── automatic_screen.dart
│   │   └── settings_screen.dart
│   │
│   └── widgets/
│       ├── direction_button.dart
│       ├── status_card.dart
│       ├── mode_selector.dart
│       └── emergency_stop_button.dart
│
└── pubspec.yaml
```

------------------------------------------------------------------------

# 16. Flutter Screens

## Home Screen

Show:

-   Connection status
-   Pico W IP address
-   Current mode
-   Current state
-   Obstacle status
-   Row count
-   Current speed

Example:

``` text
SMART MOWER

● Connected

Mode: MANUAL
State: STOPPED
Obstacle: No
Row: 0
Speed: 25000

[ MANUAL ]
[ AUTOMATIC ]

[       STOP       ]
```

------------------------------------------------------------------------

# 17. Manual Control Screen

Use directional controls:

``` text
             [ ▲ ]

        [ ◀ ] [ ■ ] [ ▶ ]

             [ ▼ ]
```

Mapping:

``` text
▲ = FORWARD
▼ = BACKWARD
◀ = LEFT
▶ = RIGHT
■ = STOP
```

Add speed control.

Do not send commands faster than necessary.

Avoid repeatedly flooding the Pico with HTTP requests.

------------------------------------------------------------------------

# 18. Automatic Screen

Show:

``` text
AUTOMATIC MODE

Status: RUNNING

State:
FORWARD

Row:
3

Obstacle:
NO

[ STOP AUTOMATIC ]
```

Allow:

-   Start automatic mode
-   Stop automatic mode
-   View current state
-   View row count
-   View obstacle status

Do not implement autonomous navigation logic in Flutter.

------------------------------------------------------------------------

# 19. Connection Management

Flutter should have:

``` text
PicoService
```

responsible for:

-   connecting to Pico
-   GET requests
-   POST requests
-   timeout handling
-   connection errors
-   parsing JSON
-   status polling

Example conceptual API:

``` dart
class PicoService {
  Future<MowerStatus> getStatus();
  Future<void> sendCommand(String command);
  Future<void> setMode(String mode);
  Future<void> setSpeed(int speed);
}
```

UI widgets should call this service rather than making HTTP requests
directly.

------------------------------------------------------------------------

# 20. Flutter Status Polling

The app can periodically request:

``` text
GET /api/status
```

For example:

``` text
Flutter
   │
   ├── status request
   │
   ├── status request
   │
   ├── status request
   │
   └── status request
```

Use a reasonable interval.

Do not continuously request the Pico at an unnecessarily high frequency.

------------------------------------------------------------------------

# 21. Phase 10 --- Testing

Test the Pico independently before testing Flutter.

## Test 1 --- Motors

Verify:

``` text
FORWARD
BACKWARD
LEFT
RIGHT
STOP
```

## Test 2 --- Ultrasonic

Verify obstacle detection at different distances.

## Test 3 --- Wi-Fi

Verify:

``` text
Pico W → Wi-Fi → IP address
```

## Test 4 --- API

Use a browser, curl, or Postman before connecting Flutter.

Test:

``` text
GET /api/health
GET /api/status
POST /api/control
POST /api/mode
POST /api/speed
```

## Test 5 --- Flutter

Verify:

-   connection
-   status
-   manual movement
-   stop
-   speed
-   automatic mode

## Test 6 --- Safety

Test:

-   invalid commands
-   invalid speed
-   Wi-Fi disconnect
-   repeated STOP
-   obstacle detection
-   switching from automatic to manual
-   switching from manual to automatic

------------------------------------------------------------------------

# 22. Important Safety Requirements

This is a physical moving machine.

Before testing motors:

-   Raise the mower/wheels off the ground for initial software tests.
-   Keep hands away from moving parts.
-   Test STOP before testing movement.
-   Test one movement command at a time.
-   Do not rely solely on the mobile app for safety.
-   Make sure the hardware has a physical power disconnect/emergency
    switch if possible.
-   Never test automatic mowing around people or animals.

------------------------------------------------------------------------

# 23. Development Order

Do NOT ask Cursor to build everything in one prompt.

Follow this order:

``` text
1. Analyze existing code
        ↓
2. Refactor Pico firmware
        ↓
3. Test motors
        ↓
4. Test ultrasonic sensor
        ↓
5. Add Wi-Fi
        ↓
6. Add HTTP server
        ↓
7. Test API with browser/Postman
        ↓
8. Add Flutter project
        ↓
9. Add PicoService
        ↓
10. Add status screen
        ↓
11. Add manual control
        ↓
12. Add speed control
        ↓
13. Add automatic mode
        ↓
14. Add emergency STOP
        ↓
15. Perform full hardware testing
```

------------------------------------------------------------------------

# 24. Final Architecture

The final system should look like:

``` text
┌───────────────────────────────────────┐
│             Flutter App               │
│                                       │
│ Home                                  │
│ Manual Control                        │
│ Automatic Mode                        │
│ Speed                                 │
│ Status                                │
│ Emergency STOP                        │
└──────────────────┬────────────────────┘
                   │
                 Wi-Fi
                   │
                   ▼
┌───────────────────────────────────────┐
│          Raspberry Pi Pico W          │
│                                       │
│ HTTP API                              │
│      │                                │
│      ▼                                │
│ Command / Mode Controller             │
│      │                                │
│      ├──────────────┐                 │
│      ▼              ▼                 │
│ Manual          Automatic             │
│ Controller      Controller            │
│      │              │                 │
│      └──────┬───────┘                 │
│             ▼                         │
│       Motor Controller                │
│             │                         │
│       ┌─────┴─────┐                   │
│       ▼           ▼                   │
│    Motors      Ultrasonic             │
│                                       │
└───────────────────────────────────────┘
```

------------------------------------------------------------------------

# 25. Definition of Done

The project is considered complete when:

-   [ ] Pico W connects to Wi-Fi.
-   [ ] Pico W exposes a working HTTP API.
-   [ ] API commands safely control the motors.
-   [ ] Ultrasonic obstacle detection works.
-   [ ] Automatic mowing works without Flutter controlling the movement
    algorithm.
-   [ ] Flutter connects to the Pico W.
-   [ ] Flutter displays live mower status.
-   [ ] Flutter supports manual movement.
-   [ ] Flutter supports automatic mode.
-   [ ] Flutter supports speed control.
-   [ ] Flutter has a clearly visible emergency STOP.
-   [ ] Invalid API requests are rejected safely.
-   [ ] Wi-Fi/network failures are handled safely.
-   [ ] Existing motor behavior has not been unintentionally changed.
-   [ ] Hardware testing has been completed safely.

------------------------------------------------------------------------

# 26. Cursor Working Principle

For every implementation step:

1.  Inspect the existing code.
2.  Explain the planned change.
3.  Make the smallest reasonable change.
4.  Show which files were changed.
5.  Explain how to test the change.
6.  Do not modify unrelated functionality.
7.  Do not replace working hardware logic without justification.
8.  Wait for successful testing before proceeding to the next major
    phase.

The priority is:

``` text
SAFETY
   ↓
HARDWARE CORRECTNESS
   ↓
PICO W COMMUNICATION
   ↓
API
   ↓
FLUTTER APP
   ↓
UI POLISH
```

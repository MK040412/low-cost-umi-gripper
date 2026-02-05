# Frequently Asked Questions

## General

### What is the UMI Gripper?
The UMI (Universal Manipulation Interface) Gripper is a robotic gripper system designed for manipulation tasks. This project provides a low-cost alternative to the original expensive implementation.

### How much does it cost to build?
The total cost is approximately $50-100 USD, compared to $500+ for the original system.

### What skills do I need?
- Basic 3D printing knowledge
- Elementary electronics (soldering, wiring)
- Basic Python programming

## Hardware

### What 3D printer do I need?
Any FDM printer with at least 150x150x150mm build volume. Recommended: Ender 3 or similar.

### Can I use different motors?
Yes, the design is adaptable. See [Hardware Guide](Hardware-Guide) for compatible alternatives.

### What microcontroller is supported?
- Arduino Uno/Nano
- ESP32 (recommended)
- Raspberry Pi Pico

## Software

### Is ROS required?
No, ROS is optional. The gripper can be controlled via Python API or serial commands.

### What operating systems are supported?
- Linux (recommended)
- Windows
- macOS

### Can I use this with my robot arm?
Yes, the gripper is designed to be compatible with standard robot arm mounting systems.

## Contributing

### How can I contribute?
See our [Contributing Guide](Contributing) for ways to help.

### I found a bug, what should I do?
Please open an issue on GitHub with:
- Description of the bug
- Steps to reproduce
- Expected vs actual behavior
- System information

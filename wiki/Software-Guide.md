# Software Guide

This guide covers the software architecture and usage of the Low-Cost UMI Gripper.

## Overview

The software module provides control systems, drivers, and interfaces for operating the gripper.

## Architecture

```
software/
├── drivers/           # Hardware drivers
├── control/           # Control algorithms
├── interfaces/        # User interfaces
├── ros/              # ROS integration
└── utils/            # Utility functions
```

## Installation

### Requirements
- Python 3.8+
- pip package manager

### Install

```bash
cd software
pip install -r requirements.txt
```

## Configuration

Configuration files are located in `software/config/`.

### Basic Configuration
(To be documented)

### Advanced Configuration
(To be documented)

## Usage

### Command Line Interface

```bash
python main.py --help
```

### Python API

```python
from gripper import Gripper

gripper = Gripper()
gripper.open()
gripper.close()
```

## ROS Integration

See [ROS Integration](ROS-Integration) for ROS2 setup and usage.

## Technical Report

For detailed technical specifications, see the [Software Technical Report](../software/technical_report/).

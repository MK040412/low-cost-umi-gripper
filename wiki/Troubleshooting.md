# Troubleshooting

Common issues and solutions for the Low-Cost UMI Gripper.

## Hardware Issues

### Gripper not moving
**Problem:** Motors don't respond to commands.

**Solutions:**
1. Check power supply voltage
2. Verify wiring connections
3. Test motor driver functionality
4. Check microcontroller serial connection

### Inconsistent grip force
**Problem:** Force readings are unstable or inaccurate.

**Solutions:**
1. Recalibrate force sensors
2. Check sensor wiring
3. Ensure proper sensor mounting
4. Replace damaged sensors

## Software Issues

### Connection failed
**Problem:** Cannot connect to gripper hardware.

**Solutions:**
1. Verify correct serial port
2. Check USB cable connection
3. Install required drivers
4. Check permissions (Linux: add user to dialout group)

```bash
sudo usermod -a -G dialout $USER
```

### Import errors
**Problem:** Python module import failures.

**Solutions:**
1. Verify Python version (3.8+)
2. Install dependencies: `pip install -r requirements.txt`
3. Check virtual environment activation

## Calibration Issues

### Sensor drift
**Problem:** Sensor readings drift over time.

**Solutions:**
1. Allow warm-up time before calibration
2. Recalibrate periodically
3. Check for temperature effects
4. Verify power supply stability

## Getting Help

If your issue isn't listed here:
1. Check [FAQ](FAQ)
2. Search [existing issues](https://github.com/MK040412/low-cost-umi-gripper/issues)
3. Open a new issue with detailed description

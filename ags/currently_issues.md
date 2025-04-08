# 🐛 Astal Bar Known Issues

## System Module

### Suspension Recovery Error

**Priority:** High **Status:** Open **Component:** System Suspension Handler

The system produces a variable error when resuming from suspension mode,
specifically displaying an "emit signal" error.

**Steps to Reproduce:**

1. Put laptop into suspension mode
2. Resume from suspension
3. Error appears referencing "Variable" with an "emit signal" error

**Expected Behavior:**

- System should resume from suspension without errors
- All signals should reconnect properly after suspension
